use std::fs::File;
use std::io::BufReader;
use std::path::{Path, PathBuf};

use chrono::{DateTime, Local, NaiveDateTime};
use exif::{In, Reader, Tag};
use thiserror::Error;
use walkdir::WalkDir;

#[derive(Debug, Error)]
pub enum MediaError {
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
    #[error("Directory not found: {0}")]
    DirectoryNotFound(PathBuf),
    #[error("No supported media files found in {0}")]
    EmptyDirectory(PathBuf),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MediaKind {
    Image,
    Video,
    Audio,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Orientation {
    Portrait,
    Landscape,
    Square,
    Panorama,
    Unknown,
}

/// Scanned media asset with extracted EXIF / filesystem metadata.
#[derive(Debug, Clone)]
pub struct ScannedAsset {
    /// Relative POSIX-style path from the scanned root (e.g. "day1/IMG_001.jpg").
    pub relative_path: String,
    pub filename: String,
    pub kind: MediaKind,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub taken_at: Option<NaiveDateTime>,
    pub camera_model: Option<String>,
}

impl ScannedAsset {
    pub fn aspect_ratio(&self) -> Option<f32> {
        match (self.width, self.height) {
            (Some(w), Some(h)) if h > 0 => Some(w as f32 / h as f32),
            _ => None,
        }
    }

    pub fn orientation(&self) -> Orientation {
        match self.aspect_ratio() {
            Some(r) if r >= 1.8 => Orientation::Panorama,
            Some(r) if r > 1.12 => Orientation::Landscape,
            Some(r) if r < 0.88 => Orientation::Portrait,
            Some(_) => Orientation::Square,
            None => Orientation::Unknown,
        }
    }

    pub fn plaque_meta(&self) -> Option<String> {
        let mut parts = Vec::new();
        if let Some(dt) = self.taken_at {
            parts.push(dt.format("%Y.%m.%d · %H:%M").to_string());
        }
        if let Some(model) = &self.camera_model {
            let trimmed = model.trim();
            if !trimmed.is_empty() {
                parts.push(trimmed.to_string());
            }
        }
        if parts.is_empty() {
            None
        } else {
            Some(parts.join(" · "))
        }
    }
}

pub fn classify_extension(path: &Path) -> Option<MediaKind> {
    let ext = path.extension()?.to_str()?.to_ascii_lowercase();
    match ext.as_str() {
        "jpg" | "jpeg" | "png" | "webp" | "heic" | "heif" | "gif" | "svg" => Some(MediaKind::Image),
        "mp4" | "mov" | "m4v" | "webm" => Some(MediaKind::Video),
        "mp3" | "wav" | "m4a" | "ogg" | "aac" => Some(MediaKind::Audio),
        _ => None,
    }
}

/// Scan a directory recursively for supported image, video, and audio files,
/// extracting EXIF timestamps, camera model, and orientation-corrected dimensions.
pub fn scan_directory(root: impl AsRef<Path>) -> Result<Vec<ScannedAsset>, MediaError> {
    let root = root.as_ref();
    if !root.exists() || !root.is_dir() {
        return Err(MediaError::DirectoryNotFound(root.to_path_buf()));
    }

    let mut assets = Vec::new();

    for entry in WalkDir::new(root).follow_links(true).into_iter().flatten() {
        let path = entry.path();
        if !path.is_file() {
            continue;
        }
        // Skip hidden files (e.g. .DS_Store)
        if path
            .file_name()
            .and_then(|n| n.to_str())
            .is_some_and(|n| n.starts_with('.'))
        {
            continue;
        }

        let Some(kind) = classify_extension(path) else {
            continue;
        };

        let rel = path
            .strip_prefix(root)
            .unwrap_or(path)
            .to_string_lossy()
            .replace('\\', "/");
        let filename = path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("untitled")
            .to_string();

        let (mut width, mut height) = match kind {
            MediaKind::Image => imagesize::size(path)
                .ok()
                .map(|sz| (Some(sz.width as u32), Some(sz.height as u32)))
                .unwrap_or((None, None)),
            _ => (None, None),
        };

        let mut taken_at = None;
        let mut camera_model = None;

        if kind == MediaKind::Image {
            if let Some(exif_info) = extract_exif(path) {
                taken_at = exif_info.taken_at;
                camera_model = exif_info.camera_model;
                if exif_info.swaps_dimensions {
                    std::mem::swap(&mut width, &mut height);
                }
            }
        }

        // Fallback to filesystem modified time if EXIF timestamp is unavailable.
        if taken_at.is_none() {
            if let Ok(meta) = path.metadata() {
                if let Ok(modified) = meta.modified() {
                    let dt: DateTime<Local> = modified.into();
                    taken_at = Some(dt.naive_local());
                }
            }
        }

        assets.push(ScannedAsset {
            relative_path: rel,
            filename,
            kind,
            width,
            height,
            taken_at,
            camera_model,
        });
    }

    if assets.is_empty() {
        return Err(MediaError::EmptyDirectory(root.to_path_buf()));
    }

    // Sort chronologically, with relative path as deterministic tie-breaker.
    assets.sort_by(|a, b| {
        a.taken_at
            .cmp(&b.taken_at)
            .then_with(|| a.relative_path.cmp(&b.relative_path))
    });

    Ok(assets)
}

struct ExifInfo {
    taken_at: Option<NaiveDateTime>,
    camera_model: Option<String>,
    swaps_dimensions: bool,
}

fn extract_exif(path: &Path) -> Option<ExifInfo> {
    let file = File::open(path).ok()?;
    let mut reader = BufReader::new(file);
    let exif = Reader::new().read_from_container(&mut reader).ok()?;

    let taken_at = [
        Tag::DateTimeOriginal,
        Tag::DateTimeDigitized,
        Tag::DateTime,
    ]
    .iter()
    .find_map(|tag| {
        let field = exif.get_field(*tag, In::PRIMARY)?;
        parse_exif_datetime(&field.display_value().to_string())
    });

    let camera_model = exif
        .get_field(Tag::Model, In::PRIMARY)
        .map(|f| f.display_value().to_string().trim_matches('"').to_string());

    // EXIF Orientation 5, 6, 7, 8 rotate the image 90 or 270 degrees.
    let swaps_dimensions = exif
        .get_field(Tag::Orientation, In::PRIMARY)
        .and_then(|f| f.value.get_uint(0))
        .is_some_and(|o| matches!(o, 5..=8));

    Some(ExifInfo {
        taken_at,
        camera_model,
        swaps_dimensions,
    })
}

fn parse_exif_datetime(raw: &str) -> Option<NaiveDateTime> {
    let cleaned = raw.trim().trim_matches('"');
    NaiveDateTime::parse_from_str(cleaned, "%Y-%m-%d %H:%M:%S")
        .or_else(|_| NaiveDateTime::parse_from_str(cleaned, "%Y:%m:%d %H:%M:%S"))
        .ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_exif_datetime_formats() {
        let dt1 = parse_exif_datetime("2026:11:02 18:42:10").unwrap();
        let dt2 = parse_exif_datetime("2026-11-02 18:42:10").unwrap();
        assert_eq!(dt1, dt2);
    }

    #[test]
    fn classifies_orientations() {
        let mk = |w, h| ScannedAsset {
            relative_path: "a.jpg".into(),
            filename: "a".into(),
            kind: MediaKind::Image,
            width: Some(w),
            height: Some(h),
            taken_at: None,
            camera_model: None,
        };
        assert_eq!(mk(2400, 1000).orientation(), Orientation::Panorama);
        assert_eq!(mk(1600, 1067).orientation(), Orientation::Landscape);
        assert_eq!(mk(1067, 1600).orientation(), Orientation::Portrait);
        assert_eq!(mk(1200, 1200).orientation(), Orientation::Square);
    }
}
