use std::path::PathBuf;

use gallery_core::{
    Atmosphere, AudioCue, GalleryManifest, LightingMood, MediaItem, Scene, SceneKind,
    SpotlightFraming, ThemePreset,
};
use gallery_export::{
    ExportOptions, export_exhibition, export_exhibition_with_options, render_html,
};
use gallery_media::{CurateOptions, curate_manifest, scan_directory};
use thiserror::Error;

uniffi::setup_scaffolding!();

#[derive(Debug, Error, uniffi::Error)]
pub enum FfiError {
    #[error("{message}")]
    Core { message: String },
    #[error("{message}")]
    Media { message: String },
    #[error("{message}")]
    Export { message: String },
    #[error("{message}")]
    InvalidArgument { message: String },
}

impl From<gallery_core::CoreError> for FfiError {
    fn from(err: gallery_core::CoreError) -> Self {
        Self::Core {
            message: err.to_string(),
        }
    }
}

impl From<gallery_media::MediaError> for FfiError {
    fn from(err: gallery_media::MediaError) -> Self {
        Self::Media {
            message: err.to_string(),
        }
    }
}

impl From<gallery_export::ExportError> for FfiError {
    fn from(err: gallery_export::ExportError) -> Self {
        Self::Export {
            message: err.to_string(),
        }
    }
}

/// Individual editable item inside a `HorizontalTrack` (photo) or `PinnedStory` (beat).
#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiSceneItem {
    pub index: u32,
    pub title: Option<String>,
    pub caption: Option<String>,
    pub media_src: Option<String>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiSceneSummary {
    pub id: String,
    pub kind: String,
    pub title: String,
    pub subtitle_or_note: Option<String>,
    pub caption: Option<String>,
    pub chapter_label: Option<String>,
    pub mood: String,
    pub asset_count: u32,
    pub has_audio: bool,
    pub audio_track: Option<String>,
    pub items: Vec<FfiSceneItem>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiManifestSummary {
    pub id: String,
    pub title: String,
    pub subtitle: Option<String>,
    pub author: Option<String>,
    pub theme_preset: String,
    pub scene_count: u32,
    pub scenes: Vec<FfiSceneSummary>,
    pub raw_json: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiExportResult {
    pub output_html: String,
    pub copied_assets: Vec<String>,
    pub missing_assets: Vec<String>,
    pub optimized_images: u32,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiPalette {
    pub background: String,
    pub surface: String,
    pub foreground: String,
    pub muted: String,
    pub accent: String,
    pub border: String,
    pub vignette: f32,
}

fn mood_to_preset_str(mood: &LightingMood) -> String {
    match mood {
        LightingMood::WarmPaper => "warm_paper".into(),
        LightingMood::SoftDim => "soft_dim".into(),
        LightingMood::DarkRoom => "dark_room".into(),
        LightingMood::Obsidian => "obsidian".into(),
        LightingMood::Custom { .. } => "custom".into(),
    }
}

fn preset_str_to_mood(preset: &str) -> Result<LightingMood, FfiError> {
    match preset {
        "warm_paper" => Ok(LightingMood::WarmPaper),
        "soft_dim" => Ok(LightingMood::SoftDim),
        "dark_room" => Ok(LightingMood::DarkRoom),
        "obsidian" => Ok(LightingMood::Obsidian),
        other => Err(FfiError::InvalidArgument {
            message: format!("Unknown lighting mood preset: {other}"),
        }),
    }
}

fn summarize_scene(scene: &Scene) -> FfiSceneSummary {
    let mut sub_items: Vec<FfiSceneItem> = Vec::new();

    let (kind, title, subtitle_or_note, caption, chapter_label) = match &scene.kind {
        SceneKind::Cover {
            title,
            subtitle,
            date_label,
            ..
        } => (
            "cover".into(),
            title.clone(),
            subtitle.clone(),
            date_label.clone(),
            None,
        ),
        SceneKind::Spotlight {
            chapter_label,
            title,
            note,
            media,
            ..
        } => (
            "spotlight".into(),
            title
                .clone()
                .or_else(|| media.caption.clone())
                .unwrap_or_else(|| "Spotlight".into()),
            note.clone(),
            media.caption.clone(),
            chapter_label.clone(),
        ),
        SceneKind::HorizontalTrack {
            chapter_label,
            intro,
            items,
            ..
        } => {
            for (idx, item) in items.iter().enumerate() {
                sub_items.push(FfiSceneItem {
                    index: idx as u32,
                    title: Some(item.alt.clone()),
                    caption: item.caption.clone(),
                    media_src: Some(item.src.clone()),
                });
            }
            (
                "horizontal_track".into(),
                format!("Horizontal Walk ({} photos)", items.len()),
                intro.clone(),
                items.first().and_then(|i| i.caption.clone()),
                chapter_label.clone(),
            )
        }
        SceneKind::PinnedStory {
            chapter_label,
            beats,
            ..
        } => {
            for (idx, beat) in beats.iter().enumerate() {
                sub_items.push(FfiSceneItem {
                    index: idx as u32,
                    title: beat.heading.clone(),
                    caption: Some(beat.body.clone()),
                    media_src: beat.media.as_ref().map(|m| m.src.clone()),
                });
            }
            (
                "pinned_story".into(),
                beats
                    .first()
                    .and_then(|b| b.heading.clone())
                    .unwrap_or_else(|| format!("Pinned Story ({} beats)", beats.len())),
                beats.first().map(|b| b.body.clone()),
                beats.first().and_then(|b| b.eyebrow.clone()),
                chapter_label.clone(),
            )
        }
        SceneKind::VideoMoment {
            chapter_label,
            caption,
            ..
        } => (
            "video_moment".into(),
            caption.clone().unwrap_or_else(|| "Video Moment".into()),
            None,
            caption.clone(),
            chapter_label.clone(),
        ),
        SceneKind::Ending { title, message, .. } => (
            "ending".into(),
            title.clone(),
            message.clone(),
            None,
            Some("Fin".into()),
        ),
    };

    FfiSceneSummary {
        id: scene.id.clone(),
        kind,
        title,
        subtitle_or_note,
        caption,
        chapter_label,
        mood: mood_to_preset_str(&scene.atmosphere.mood),
        asset_count: scene.referenced_assets().len() as u32,
        has_audio: scene.atmosphere.audio.is_some(),
        audio_track: scene.atmosphere.audio.as_ref().map(|a| a.track.clone()),
        items: sub_items,
    }
}

fn summarize_manifest(manifest: &GalleryManifest) -> Result<FfiManifestSummary, FfiError> {
    let raw_json = manifest.to_json_pretty()?;
    let scenes: Vec<FfiSceneSummary> = manifest.scenes.iter().map(summarize_scene).collect();
    Ok(FfiManifestSummary {
        id: manifest.id.clone(),
        title: manifest.title.clone(),
        subtitle: manifest.subtitle.clone(),
        author: manifest.author.clone(),
        theme_preset: manifest.theme.preset.as_str().into(),
        scene_count: scenes.len() as u32,
        scenes,
        raw_json,
    })
}

fn normalize_optional(val: Option<String>) -> Option<String> {
    val.and_then(|s| {
        let trimmed = s.trim().to_string();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed)
        }
    })
}

/// Switch the exhibition's visual theme preset (`editorial_gallery`, `toss_clean`, `midnight_film`, `atelier_poster`).
#[uniffi::export]
pub fn update_theme_preset(
    json: String,
    theme_preset: String,
) -> Result<FfiManifestSummary, FfiError> {
    let mut manifest = GalleryManifest::from_json_str(&json)?;
    let preset = ThemePreset::from_preset_str(&theme_preset).ok_or_else(|| {
        FfiError::InvalidArgument {
            message: format!("Unknown theme preset: {theme_preset}"),
        }
    })?;
    manifest.theme.preset = preset;
    summarize_manifest(&manifest)
}

/// Resolve exact CSS palette & vignette for a lighting mood preset (for live WKWebView patching).
#[uniffi::export]
pub fn resolve_mood_palette(mood_preset: String) -> Result<FfiPalette, FfiError> {
    let mood = preset_str_to_mood(&mood_preset)?;
    let p = mood.resolve();
    let vignette = match mood {
        LightingMood::DarkRoom => 0.35,
        LightingMood::Obsidian => 0.55,
        _ => 0.0,
    };
    Ok(FfiPalette {
        background: p.background,
        surface: p.surface,
        foreground: p.foreground,
        muted: p.muted,
        accent: p.accent,
        border: p.border,
        vignette,
    })
}

#[uniffi::export]
pub fn scan_folder_to_manifest(
    input_dir: String,
    title: String,
    subtitle: Option<String>,
    gap_hours: i64,
) -> Result<FfiManifestSummary, FfiError> {
    let assets = scan_directory(&input_dir)?;
    let manifest = curate_manifest(
        &assets,
        CurateOptions {
            title,
            subtitle,
            author: None,
            chapter_gap_hours: gap_hours.max(1),
        },
    );
    summarize_manifest(&manifest)
}

#[uniffi::export]
pub fn load_manifest_from_file(manifest_path: String) -> Result<FfiManifestSummary, FfiError> {
    let mut path = PathBuf::from(&manifest_path);
    if path.is_dir() {
        path = path.join("manifest.json");
    }
    let manifest = GalleryManifest::load_from_path(&path)?;
    summarize_manifest(&manifest)
}

#[uniffi::export]
pub fn parse_manifest_json(json: String) -> Result<FfiManifestSummary, FfiError> {
    let manifest = GalleryManifest::from_json_str(&json)?;
    summarize_manifest(&manifest)
}

#[uniffi::export]
pub fn save_manifest_json(manifest_path: String, json: String) -> Result<(), FfiError> {
    let manifest = GalleryManifest::from_json_str(&json)?;
    manifest.save_to_path(&manifest_path)?;
    Ok(())
}

#[uniffi::export]
pub fn update_scene_mood(
    json: String,
    scene_id: String,
    mood_preset: String,
) -> Result<FfiManifestSummary, FfiError> {
    let mut manifest = GalleryManifest::from_json_str(&json)?;
    let mood = preset_str_to_mood(&mood_preset)?;
    let scene = manifest
        .scenes
        .iter_mut()
        .find(|s| s.id == scene_id)
        .ok_or_else(|| FfiError::InvalidArgument {
            message: format!("Scene not found: {scene_id}"),
        })?;
    scene.atmosphere.vignette = match mood {
        LightingMood::DarkRoom => 0.35,
        LightingMood::Obsidian => 0.55,
        _ => 0.0,
    };
    scene.atmosphere.mood = mood;
    summarize_manifest(&manifest)
}

#[uniffi::export]
pub fn update_scene_text(
    json: String,
    scene_id: String,
    title: Option<String>,
    subtitle_or_note: Option<String>,
    caption: Option<String>,
    chapter_label: Option<String>,
) -> Result<FfiManifestSummary, FfiError> {
    let mut manifest = GalleryManifest::from_json_str(&json)?;
    let scene = manifest
        .scenes
        .iter_mut()
        .find(|s| s.id == scene_id)
        .ok_or_else(|| FfiError::InvalidArgument {
            message: format!("Scene not found: {scene_id}"),
        })?;

    let clean_title = normalize_optional(title);
    let clean_note = normalize_optional(subtitle_or_note);
    let clean_caption = normalize_optional(caption);
    let clean_chapter = normalize_optional(chapter_label);

    match &mut scene.kind {
        SceneKind::Cover {
            title: t,
            subtitle: s,
            date_label: d,
            ..
        } => {
            if let Some(new_t) = clean_title {
                *t = new_t.clone();
                manifest.title = new_t;
            }
            *s = clean_note;
            *d = clean_caption;
        }
        SceneKind::Spotlight {
            chapter_label: ch,
            title: t,
            note: n,
            media,
            ..
        } => {
            *ch = clean_chapter;
            *t = clean_title;
            *n = clean_note;
            media.caption = clean_caption;
        }
        SceneKind::HorizontalTrack {
            chapter_label: ch,
            intro,
            ..
        } => {
            *ch = clean_chapter;
            *intro = clean_note;
        }
        SceneKind::PinnedStory {
            chapter_label: ch,
            ..
        } => {
            *ch = clean_chapter;
        }
        SceneKind::VideoMoment {
            chapter_label: ch,
            caption: c,
            ..
        } => {
            *ch = clean_chapter;
            *c = clean_caption.or(clean_title);
        }
        SceneKind::Ending {
            title: t,
            message: m,
            ..
        } => {
            if let Some(new_t) = clean_title {
                *t = new_t;
            }
            *m = clean_note;
        }
    }

    summarize_manifest(&manifest)
}

/// Update an individual photo in `HorizontalTrack` or beat in `PinnedStory`.
#[uniffi::export]
pub fn update_scene_item(
    json: String,
    scene_id: String,
    item_index: u32,
    title: Option<String>,
    caption: Option<String>,
) -> Result<FfiManifestSummary, FfiError> {
    let mut manifest = GalleryManifest::from_json_str(&json)?;
    let scene = manifest
        .scenes
        .iter_mut()
        .find(|s| s.id == scene_id)
        .ok_or_else(|| FfiError::InvalidArgument {
            message: format!("Scene not found: {scene_id}"),
        })?;
    let idx = item_index as usize;

    match &mut scene.kind {
        SceneKind::HorizontalTrack { items, .. } => {
            let item = items.get_mut(idx).ok_or_else(|| FfiError::InvalidArgument {
                message: format!("Item index {idx} out of bounds"),
            })?;
            if let Some(t) = normalize_optional(title) {
                item.alt = t;
            }
            item.caption = normalize_optional(caption);
        }
        SceneKind::PinnedStory { beats, .. } => {
            let beat = beats.get_mut(idx).ok_or_else(|| FfiError::InvalidArgument {
                message: format!("Beat index {idx} out of bounds"),
            })?;
            beat.heading = normalize_optional(title);
            if let Some(body) = normalize_optional(caption) {
                beat.body = body;
            }
        }
        _ => {
            return Err(FfiError::InvalidArgument {
                message: "Scene does not support sub-item editing".into(),
            });
        }
    }

    summarize_manifest(&manifest)
}

/// Remove an individual photo from `HorizontalTrack` or beat from `PinnedStory`.
#[uniffi::export]
pub fn remove_scene_item(
    json: String,
    scene_id: String,
    item_index: u32,
) -> Result<FfiManifestSummary, FfiError> {
    let mut manifest = GalleryManifest::from_json_str(&json)?;
    let scene = manifest
        .scenes
        .iter_mut()
        .find(|s| s.id == scene_id)
        .ok_or_else(|| FfiError::InvalidArgument {
            message: format!("Scene not found: {scene_id}"),
        })?;
    let idx = item_index as usize;

    match &mut scene.kind {
        SceneKind::HorizontalTrack { items, .. } => {
            if items.len() <= 1 {
                return Err(FfiError::InvalidArgument {
                    message: "가로 갤러리에는 최소 1장의 사진이 필요합니다.".into(),
                });
            }
            if idx >= items.len() {
                return Err(FfiError::InvalidArgument {
                    message: format!("Item index {idx} out of bounds"),
                });
            }
            items.remove(idx);
        }
        SceneKind::PinnedStory { beats, .. } => {
            if beats.len() <= 1 {
                return Err(FfiError::InvalidArgument {
                    message: "스토리 씬에는 최소 1개의 비트가 필요합니다.".into(),
                });
            }
            if idx >= beats.len() {
                return Err(FfiError::InvalidArgument {
                    message: format!("Beat index {idx} out of bounds"),
                });
            }
            beats.remove(idx);
        }
        _ => {
            return Err(FfiError::InvalidArgument {
                message: "Scene does not support sub-item removal".into(),
            });
        }
    }

    summarize_manifest(&manifest)
}

#[uniffi::export]
pub fn set_scene_audio(
    json: String,
    scene_id: String,
    audio_track: Option<String>,
    volume: f32,
) -> Result<FfiManifestSummary, FfiError> {
    let mut manifest = GalleryManifest::from_json_str(&json)?;
    let scene = manifest
        .scenes
        .iter_mut()
        .find(|s| s.id == scene_id)
        .ok_or_else(|| FfiError::InvalidArgument {
            message: format!("Scene not found: {scene_id}"),
        })?;

    scene.atmosphere.audio = normalize_optional(audio_track).map(|track| AudioCue {
        track,
        volume: volume.clamp(0.0, 1.0),
        fade_ms: 1400,
        loop_audio: true,
    });

    summarize_manifest(&manifest)
}

#[uniffi::export]
pub fn add_spotlight_scene(
    json: String,
    image_rel_path: String,
    title: String,
    caption: Option<String>,
    mood_preset: String,
) -> Result<FfiManifestSummary, FfiError> {
    let mut manifest = GalleryManifest::from_json_str(&json)?;
    let mood = preset_str_to_mood(&mood_preset)?;
    let scene = Scene::new(
        Atmosphere::with_mood(mood),
        SceneKind::Spotlight {
            chapter_label: Some(format!("Room {:02}", manifest.scenes.len())),
            title: normalize_optional(Some(title.clone())),
            note: None,
            media: MediaItem {
                src: image_rel_path,
                alt: title,
                caption: normalize_optional(caption),
                meta: None,
                width: None,
                height: None,
            },
            framing: SpotlightFraming::MuseumFrame,
        },
    );

    if let Some(ending_pos) = manifest
        .scenes
        .iter()
        .position(|s| matches!(s.kind, SceneKind::Ending { .. }))
    {
        manifest.scenes.insert(ending_pos, scene);
    } else {
        manifest.scenes.push(scene);
    }

    summarize_manifest(&manifest)
}

#[uniffi::export]
pub fn delete_scene(json: String, scene_id: String) -> Result<FfiManifestSummary, FfiError> {
    let mut manifest = GalleryManifest::from_json_str(&json)?;
    if manifest.scenes.len() <= 1 {
        return Err(FfiError::InvalidArgument {
            message: "전시관에는 최소 1개의 씬이 남아 있어야 합니다.".into(),
        });
    }
    let before = manifest.scenes.len();
    manifest.scenes.retain(|s| s.id != scene_id);
    if manifest.scenes.len() == before {
        return Err(FfiError::InvalidArgument {
            message: format!("Scene not found: {scene_id}"),
        });
    }
    summarize_manifest(&manifest)
}

#[uniffi::export]
pub fn reorder_scenes(
    json: String,
    from_index: u32,
    to_index: u32,
) -> Result<FfiManifestSummary, FfiError> {
    let mut manifest = GalleryManifest::from_json_str(&json)?;
    let from = from_index as usize;
    let to = to_index as usize;
    if from >= manifest.scenes.len() || to >= manifest.scenes.len() {
        return Err(FfiError::InvalidArgument {
            message: format!(
                "Scene index out of bounds (from={from}, to={to}, len={})",
                manifest.scenes.len()
            ),
        });
    }
    let scene = manifest.scenes.remove(from);
    manifest.scenes.insert(to, scene);
    summarize_manifest(&manifest)
}

/// Export a standard exhibition folder (`index.html` + `assets/`) with automatic 2048px image optimization.
#[uniffi::export]
pub fn export_manifest_to_folder(
    json: String,
    source_root: String,
    output_dir: String,
) -> Result<FfiExportResult, FfiError> {
    let manifest = GalleryManifest::from_json_str(&json)?;
    let report = export_exhibition(&manifest, &source_root, &output_dir)?;
    Ok(FfiExportResult {
        output_html: report.output_html.to_string_lossy().into_owned(),
        copied_assets: report.copied_assets,
        missing_assets: report.missing_assets,
        optimized_images: report.optimized_images as u32,
    })
}

/// Export a single self-contained HTML file (`exhibition-single.html`) with inline CSS/JS & Base64 media
/// so it opens cleanly via AirDrop, iOS Files, or email without broken relative links.
#[uniffi::export]
pub fn export_manifest_single_file(
    json: String,
    source_root: String,
    output_dir: String,
) -> Result<FfiExportResult, FfiError> {
    let manifest = GalleryManifest::from_json_str(&json)?;
    let report = export_exhibition_with_options(
        &manifest,
        &source_root,
        &output_dir,
        ExportOptions {
            max_image_edge: Some(1600),
            jpeg_quality: 82,
            single_file_html: true,
        },
    )?;
    Ok(FfiExportResult {
        output_html: report.output_html.to_string_lossy().into_owned(),
        copied_assets: report.copied_assets,
        missing_assets: report.missing_assets,
        optimized_images: report.optimized_images as u32,
    })
}

#[uniffi::export]
pub fn render_preview_html(json: String) -> Result<String, FfiError> {
    let manifest = GalleryManifest::from_json_str(&json)?;
    Ok(render_html(&manifest)?)
}

#[cfg(test)]
mod tests {
    use super::*;
    use gallery_core::{Atmosphere, Scene, SceneKind};

    #[test]
    fn updates_mood_text_items_and_reorders_scenes() {
        let manifest = GalleryManifest::new(
            "FFI Test",
            vec![
                Scene::new(
                    Atmosphere::with_mood(LightingMood::WarmPaper),
                    SceneKind::HorizontalTrack {
                        chapter_label: Some("Walk".into()),
                        intro: Some("Intro".into()),
                        items: vec![
                            MediaItem {
                                src: "images/a.svg".into(),
                                alt: "A".into(),
                                caption: Some("First".into()),
                                meta: None,
                                width: None,
                                height: None,
                            },
                            MediaItem {
                                src: "images/b.svg".into(),
                                alt: "B".into(),
                                caption: Some("Second".into()),
                                meta: None,
                                width: None,
                                height: None,
                            },
                        ],
                        pace_multiplier: 1.0,
                    },
                ),
                Scene::new(
                    Atmosphere::with_mood(LightingMood::WarmPaper),
                    SceneKind::Ending {
                        title: "Fin".into(),
                        message: None,
                        credits: vec![],
                        replay_label: "Top".into(),
                    },
                ),
            ],
        );
        let json = manifest.to_json_pretty().unwrap();
        let track_id = manifest.scenes[0].id.clone();

        let edited = update_scene_item(
            json,
            track_id.clone(),
            1,
            None,
            Some("Updated Second Caption".into()),
        )
        .unwrap();
        assert_eq!(
            edited.scenes[0].items[1].caption.as_deref(),
            Some("Updated Second Caption")
        );

        let trimmed = remove_scene_item(edited.raw_json, track_id, 0).unwrap();
        assert_eq!(trimmed.scenes[0].items.len(), 1);
        assert_eq!(
            trimmed.scenes[0].items[0].caption.as_deref(),
            Some("Updated Second Caption")
        );
    }
}
