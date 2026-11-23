use std::collections::HashMap;
use std::fs::{self, File};
use std::io::{BufReader, Cursor};
use std::path::{Path, PathBuf};

use base64::Engine as _;
use base64::engine::general_purpose::STANDARD as BASE64;
use exif::{In, Reader as ExifReader, Tag};
use gallery_core::{
    AudioCue, GalleryManifest, MediaItem, ResolvedPalette, Scene, SceneKind, SpotlightFraming,
    StoryBeat,
};
use image::ImageReader;
use image::codecs::jpeg::JpegEncoder;
use image::imageops::FilterType;
use serde::Serialize;
use tera::{Context, Tera};
use thiserror::Error;

use crate::script::render_runtime_js;
use crate::styles::render_stylesheet;

const EXHIBITION_TEMPLATE: &str = include_str!("../templates/exhibition.html");

#[derive(Debug, Error)]
pub enum ExportError {
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
    #[error("Template rendering error: {0}")]
    Template(#[from] tera::Error),
    #[error("Manifest error: {0}")]
    Core(#[from] gallery_core::CoreError),
}

#[derive(Debug, Clone)]
pub struct ExportOptions {
    /// Maximum width or height in pixels for raster images (JPEG/PNG/WebP).
    /// `None` disables resizing and copies original bytes.
    pub max_image_edge: Option<u32>,
    /// JPEG encoding quality (1..=100) for resized JPEG/WebP images.
    pub jpeg_quality: u8,
    /// When true, exports a single self-contained HTML file with inline CSS/JS
    /// and Base64 data URIs (works via AirDrop / iOS Files / email with zero broken links).
    pub single_file_html: bool,
}

impl Default for ExportOptions {
    fn default() -> Self {
        Self {
            max_image_edge: Some(2048),
            jpeg_quality: 85,
            single_file_html: false,
        }
    }
}

#[derive(Debug, Clone)]
pub struct ExportReport {
    pub output_html: PathBuf,
    pub copied_assets: Vec<String>,
    pub missing_assets: Vec<String>,
    pub optimized_images: usize,
}

#[derive(Debug, Serialize)]
struct RenderScene {
    id: String,
    kind_name: &'static str,
    palette: ResolvedPalette,
    vignette: f32,
    audio: Option<AudioCue>,
    audio_href: Option<String>,
    title: Option<String>,
    subtitle: Option<String>,
    date_label: Option<String>,
    hero_image: Option<MediaItem>,
    has_hero: bool,
    enter_label: Option<String>,
    chapter_label: Option<String>,
    note: Option<String>,
    media: Option<MediaItem>,
    framing: Option<&'static str>,
    intro: Option<String>,
    items: Vec<MediaItem>,
    pace_multiplier: f32,
    beats: Vec<StoryBeat>,
    video_src: Option<String>,
    poster: Option<String>,
    caption: Option<String>,
    muted_autoplay: bool,
    loop_video: bool,
    message: Option<String>,
    credits: Vec<String>,
    replay_label: Option<String>,
}

impl RenderScene {
    fn from_scene(scene: &Scene, resolve_href: &dyn Fn(&str) -> String) -> Self {
        let palette = scene.atmosphere.mood.resolve();
        let resolve_media = |m: &MediaItem| {
            let mut copy = m.clone();
            copy.src = resolve_href(&m.src);
            copy
        };

        let mut out = Self {
            id: scene.id.clone(),
            kind_name: "",
            palette,
            vignette: scene.atmosphere.vignette.clamp(0.0, 1.0),
            audio_href: scene
                .atmosphere
                .audio
                .as_ref()
                .map(|a| resolve_href(&a.track)),
            audio: scene.atmosphere.audio.clone(),
            title: None,
            subtitle: None,
            date_label: None,
            hero_image: None,
            has_hero: false,
            enter_label: None,
            chapter_label: None,
            note: None,
            media: None,
            framing: None,
            intro: None,
            items: Vec::new(),
            pace_multiplier: 1.0,
            beats: Vec::new(),
            video_src: None,
            poster: None,
            caption: None,
            muted_autoplay: true,
            loop_video: true,
            message: None,
            credits: Vec::new(),
            replay_label: None,
        };

        match &scene.kind {
            SceneKind::Cover {
                title,
                subtitle,
                date_label,
                hero_image,
                enter_label,
            } => {
                out.kind_name = "cover";
                out.title = Some(title.clone());
                out.subtitle = subtitle.clone();
                out.date_label = date_label.clone();
                out.has_hero = hero_image.is_some();
                out.hero_image = hero_image.as_ref().map(resolve_media);
                out.enter_label = Some(enter_label.clone());
            }
            SceneKind::Spotlight {
                chapter_label,
                title,
                note,
                media,
                framing,
            } => {
                out.kind_name = "spotlight";
                out.chapter_label = chapter_label.clone();
                out.title = title.clone();
                out.note = note.clone();
                out.media = Some(resolve_media(media));
                out.framing = Some(match framing {
                    SpotlightFraming::MuseumFrame => "museum_frame",
                    SpotlightFraming::FullBleed => "full_bleed",
                    SpotlightFraming::EditorialSplit => "editorial_split",
                });
            }
            SceneKind::HorizontalTrack {
                chapter_label,
                intro,
                items,
                pace_multiplier,
            } => {
                out.kind_name = "horizontal_track";
                out.chapter_label = chapter_label.clone();
                out.intro = intro.clone();
                out.items = items.iter().map(resolve_media).collect();
                out.pace_multiplier = *pace_multiplier;
            }
            SceneKind::PinnedStory {
                chapter_label,
                beats,
                pace_multiplier,
            } => {
                out.kind_name = "pinned_story";
                out.chapter_label = chapter_label.clone();
                out.beats = beats
                    .iter()
                    .map(|b| StoryBeat {
                        eyebrow: b.eyebrow.clone(),
                        heading: b.heading.clone(),
                        body: b.body.clone(),
                        media: b.media.as_ref().map(resolve_media),
                    })
                    .collect();
                out.pace_multiplier = *pace_multiplier;
            }
            SceneKind::VideoMoment {
                chapter_label,
                src,
                poster,
                caption,
                muted_autoplay,
                loop_video,
            } => {
                out.kind_name = "video_moment";
                out.chapter_label = chapter_label.clone();
                out.video_src = Some(resolve_href(src));
                out.poster = poster.as_deref().map(resolve_href);
                out.caption = caption.clone();
                out.muted_autoplay = *muted_autoplay;
                out.loop_video = *loop_video;
            }
            SceneKind::Ending {
                title,
                message,
                credits,
                replay_label,
            } => {
                out.kind_name = "ending";
                out.title = Some(title.clone());
                out.message = message.clone();
                out.credits = credits.clone();
                out.replay_label = Some(replay_label.clone());
            }
        }

        out
    }
}

/// Render the HTML string for a manifest using standard `assets/<rel>` references.
pub fn render_html(manifest: &GalleryManifest) -> Result<String, ExportError> {
    render_html_internal(manifest, None, None, &|rel| format!("assets/{rel}"))
}

fn render_html_internal(
    manifest: &GalleryManifest,
    inline_css: Option<String>,
    inline_js: Option<&str>,
    resolve_href: &dyn Fn(&str) -> String,
) -> Result<String, ExportError> {
    manifest.validate()?;

    let mut tera = Tera::default();
    tera.add_raw_template("exhibition.html", EXHIBITION_TEMPLATE)?;

    let render_scenes: Vec<RenderScene> = manifest
        .scenes
        .iter()
        .map(|s| RenderScene::from_scene(s, resolve_href))
        .collect();
    let has_audio = manifest.scenes.iter().any(|s| s.atmosphere.audio.is_some());

    // Pick OG preview image (Cover hero image or first photo in the exhibition).
    let og_image = find_first_image_rel(manifest)
        .filter(|_| inline_css.is_none()) // Avoid huge data: URI in <meta og:image>
        .map(|rel| resolve_href(&rel));

    let mut ctx = Context::new();
    ctx.insert("title", &manifest.title);
    ctx.insert("subtitle", &manifest.subtitle);
    ctx.insert("has_audio", &has_audio);
    ctx.insert("scenes", &render_scenes);
    ctx.insert("og_image", &og_image);
    ctx.insert("theme_preset", manifest.theme.preset.as_str());
    ctx.insert("inline_css", &inline_css);
    ctx.insert("inline_js", &inline_js);

    Ok(tera.render("exhibition.html", &ctx)?)
}

fn find_first_image_rel(manifest: &GalleryManifest) -> Option<String> {
    for scene in &manifest.scenes {
        match &scene.kind {
            SceneKind::Cover {
                hero_image: Some(img),
                ..
            } => return Some(img.src.clone()),
            SceneKind::Spotlight { media, .. } => return Some(media.src.clone()),
            SceneKind::HorizontalTrack { items, .. } if !items.is_empty() => {
                return Some(items[0].src.clone());
            }
            _ => {}
        }
    }
    None
}

/// Export a standalone exhibition folder (`index.html` + `assets/`) with automatic
/// image optimization (EXIF orientation + max 2048px resize).
pub fn export_exhibition(
    manifest: &GalleryManifest,
    source_root: impl AsRef<Path>,
    output_dir: impl AsRef<Path>,
) -> Result<ExportReport, ExportError> {
    export_exhibition_with_options(manifest, source_root, output_dir, ExportOptions::default())
}

/// Export an exhibition with explicit optimization & single-file HTML options.
pub fn export_exhibition_with_options(
    manifest: &GalleryManifest,
    source_root: impl AsRef<Path>,
    output_dir: impl AsRef<Path>,
    options: ExportOptions,
) -> Result<ExportReport, ExportError> {
    let source_root = source_root.as_ref();
    let output_dir = output_dir.as_ref();
    fs::create_dir_all(output_dir)?;

    let css = render_stylesheet(&manifest.theme);
    let js = render_runtime_js();

    let mut copied_assets = Vec::new();
    let mut missing_assets = Vec::new();
    let mut optimized_images = 0usize;

    if options.single_file_html {
        let mut data_uris: HashMap<String, String> = HashMap::new();

        for rel in manifest.referenced_assets() {
            let src_path = source_root.join(&rel);
            if src_path.exists() && src_path.is_file() {
                let (bytes, mime, was_optimized) =
                    load_and_optimize_asset(&src_path, options.max_image_edge, options.jpeg_quality)?;
                if was_optimized {
                    optimized_images += 1;
                }
                let uri = format!("data:{mime};base64,{}", BASE64.encode(&bytes));
                data_uris.insert(rel.clone(), uri);
                copied_assets.push(rel);
            } else {
                missing_assets.push(rel);
            }
        }

        let html = render_html_internal(manifest, Some(css), Some(js), &|rel| {
            data_uris
                .get(rel)
                .cloned()
                .unwrap_or_else(|| format!("assets/{rel}"))
        })?;

        let output_html = output_dir.join("exhibition-single.html");
        fs::write(&output_html, html)?;

        return Ok(ExportReport {
            output_html,
            copied_assets,
            missing_assets,
            optimized_images,
        });
    }

    // Standard folder export (`index.html` + `assets/`)
    let assets_dir = output_dir.join("assets");
    fs::create_dir_all(&assets_dir)?;

    let html = render_html(manifest)?;
    let output_html = output_dir.join("index.html");
    fs::write(&output_html, html)?;
    fs::write(assets_dir.join("gallery.css"), css)?;
    fs::write(assets_dir.join("gallery.js"), js)?;

    for rel in manifest.referenced_assets() {
        let src_path = source_root.join(&rel);
        if src_path.exists() && src_path.is_file() {
            let dst_path = assets_dir.join(&rel);
            if let Some(parent) = dst_path.parent() {
                fs::create_dir_all(parent)?;
            }
            let (bytes, _mime, was_optimized) =
                load_and_optimize_asset(&src_path, options.max_image_edge, options.jpeg_quality)?;
            if was_optimized {
                optimized_images += 1;
                fs::write(&dst_path, bytes)?;
            } else {
                fs::copy(&src_path, &dst_path)?;
            }
            copied_assets.push(rel);
        } else {
            missing_assets.push(rel);
        }
    }

    Ok(ExportReport {
        output_html,
        copied_assets,
        missing_assets,
        optimized_images,
    })
}

/// Optimize raster images (EXIF orientation fix + resize to `max_edge` + JPEG compression).
/// Non-raster files (SVG, WAV, MP3, MP4, GIF) are returned verbatim with their MIME type.
fn load_and_optimize_asset(
    path: &Path,
    max_edge: Option<u32>,
    jpeg_quality: u8,
) -> Result<(Vec<u8>, &'static str, bool), ExportError> {
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();

    let mime = match ext.as_str() {
        "jpg" | "jpeg" => "image/jpeg",
        "png" => "image/png",
        "webp" => "image/webp",
        "gif" => "image/gif",
        "svg" => "image/svg+xml",
        "wav" => "audio/wav",
        "mp3" => "audio/mpeg",
        "m4a" => "audio/mp4",
        "ogg" => "audio/ogg",
        "mp4" | "m4v" => "video/mp4",
        "mov" => "video/quicktime",
        "webm" => "video/webm",
        _ => "application/octet-stream",
    };

    let is_optimizable_raster = matches!(ext.as_str(), "jpg" | "jpeg" | "png" | "webp");
    if is_optimizable_raster {
        if let Some(limit) = max_edge {
            if let Ok(reader) = ImageReader::open(path) {
                if let Ok(mut img) = reader.decode() {
                    let orientation = read_exif_orientation(path).unwrap_or(1);
                    let needs_orient = orientation != 1;
                    let (w, h) = (img.width(), img.height());
                    let needs_resize = w.max(h) > limit;

                    if needs_orient || needs_resize {
                        img = apply_exif_orientation(img, orientation);
                        if needs_resize {
                            img = img.resize(limit, limit, FilterType::Triangle);
                        }
                        let mut out = Cursor::new(Vec::new());
                        if ext == "png" {
                            if img.write_to(&mut out, image::ImageFormat::Png).is_ok() {
                                return Ok((out.into_inner(), "image/png", true));
                            }
                        } else {
                            let rgb = img.to_rgb8();
                            let mut enc = JpegEncoder::new_with_quality(&mut out, jpeg_quality);
                            if enc.encode_image(&rgb).is_ok() {
                                return Ok((out.into_inner(), "image/jpeg", true));
                            }
                        }
                    }
                }
            }
        }
    }

    let raw = fs::read(path)?;
    Ok((raw, mime, false))
}

fn read_exif_orientation(path: &Path) -> Option<u32> {
    let file = File::open(path).ok()?;
    let mut reader = BufReader::new(file);
    let exif = ExifReader::new().read_from_container(&mut reader).ok()?;
    exif.get_field(Tag::Orientation, In::PRIMARY)?
        .value
        .get_uint(0)
}

fn apply_exif_orientation(img: image::DynamicImage, orientation: u32) -> image::DynamicImage {
    match orientation {
        2 => img.fliph(),
        3 => img.rotate180(),
        4 => img.flipv(),
        5 => img.rotate90().fliph(),
        6 => img.rotate90(),
        7 => img.rotate270().fliph(),
        8 => img.rotate270(),
        _ => img,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use gallery_core::{Atmosphere, LightingMood, Scene, SceneKind};

    #[test]
    fn renders_og_tags_and_bridge_hooks() {
        let manifest = GalleryManifest::new(
            "Test Exhibition",
            vec![
                Scene::new(
                    Atmosphere::with_mood(LightingMood::WarmPaper),
                    SceneKind::Cover {
                        title: "Test Exhibition".into(),
                        subtitle: Some("A quiet stroll".into()),
                        date_label: Some("2026.11".into()),
                        hero_image: Some(MediaItem {
                            src: "img/hero.jpg".into(),
                            alt: "Hero".into(),
                            caption: None,
                            meta: None,
                            width: None,
                            height: None,
                        }),
                        enter_label: "전시 입장하기".into(),
                    },
                ),
                Scene::new(
                    Atmosphere::with_mood(LightingMood::DarkRoom),
                    SceneKind::HorizontalTrack {
                        chapter_label: Some("Room 01".into()),
                        intro: Some("Walk sideways".into()),
                        items: vec![MediaItem {
                            src: "img/1.svg".into(),
                            alt: "First".into(),
                            caption: Some("Caption 1".into()),
                            meta: None,
                            width: None,
                            height: None,
                        }],
                        pace_multiplier: 1.2,
                    },
                ),
                Scene::new(
                    Atmosphere::with_mood(LightingMood::Obsidian),
                    SceneKind::Ending {
                        title: "Fin".into(),
                        message: Some("Thank you".into()),
                        credits: vec!["1 Photo".into()],
                        replay_label: "처음으로".into(),
                    },
                ),
            ],
        );

        let html = render_html(&manifest).expect("render html");
        assert!(html.contains("property=\"og:title\" content=\"Test Exhibition\""));
        assert!(html.contains("property=\"og:image\" content=\"assets/img/hero.jpg\""));
        assert!(html.contains("data-field=\"title\""));
        assert!(html.contains("data-item-index=\"0\""));
    }
}
