use std::fs;
use std::path::Path;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use thiserror::Error;
use uuid::Uuid;

use crate::scene::{Scene, SceneKind};
use crate::theme::ThemeConfig;

pub const CURRENT_SCHEMA_VERSION: &str = "0.1.0";

#[derive(Debug, Error)]
pub enum CoreError {
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
    #[error("JSON serialization error: {0}")]
    Json(#[from] serde_json::Error),
    #[error("Manifest validation error: {0}")]
    Validation(String),
}

/// Top-level exhibition project manifest (`manifest.json` inside a `.gallery` package).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GalleryManifest {
    #[serde(default = "default_schema_version")]
    pub schema_version: String,
    #[serde(default = "new_gallery_id")]
    pub id: String,
    pub title: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub subtitle: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub author: Option<String>,
    #[serde(default = "Utc::now")]
    pub created_at: DateTime<Utc>,
    #[serde(default)]
    pub theme: ThemeConfig,
    pub scenes: Vec<Scene>,
}

fn default_schema_version() -> String {
    CURRENT_SCHEMA_VERSION.into()
}

fn new_gallery_id() -> String {
    Uuid::new_v4().to_string()
}

impl GalleryManifest {
    pub fn new(title: impl Into<String>, scenes: Vec<Scene>) -> Self {
        Self {
            schema_version: CURRENT_SCHEMA_VERSION.into(),
            id: new_gallery_id(),
            title: title.into(),
            subtitle: None,
            author: None,
            created_at: Utc::now(),
            theme: ThemeConfig::default(),
            scenes,
        }
    }

    pub fn from_json_str(json: &str) -> Result<Self, CoreError> {
        let manifest: Self = serde_json::from_str(json)?;
        manifest.validate()?;
        Ok(manifest)
    }

    pub fn to_json_pretty(&self) -> Result<String, CoreError> {
        Ok(serde_json::to_string_pretty(self)?)
    }

    pub fn load_from_path(path: impl AsRef<Path>) -> Result<Self, CoreError> {
        let content = fs::read_to_string(path)?;
        Self::from_json_str(&content)
    }

    pub fn save_to_path(&self, path: impl AsRef<Path>) -> Result<(), CoreError> {
        let json = self.to_json_pretty()?;
        fs::write(path, json)?;
        Ok(())
    }

    /// Validate structural invariants of the exhibition manifest.
    pub fn validate(&self) -> Result<(), CoreError> {
        if self.title.trim().is_empty() {
            return Err(CoreError::Validation("Gallery title cannot be empty".into()));
        }
        if self.scenes.is_empty() {
            return Err(CoreError::Validation(
                "Gallery must contain at least one scene".into(),
            ));
        }
        for scene in &self.scenes {
            match &scene.kind {
                SceneKind::HorizontalTrack {
                    items,
                    pace_multiplier,
                    ..
                } => {
                    if items.is_empty() {
                        return Err(CoreError::Validation(format!(
                            "HorizontalTrack scene '{}' must have at least one item",
                            scene.id
                        )));
                    }
                    if *pace_multiplier <= 0.0 {
                        return Err(CoreError::Validation(format!(
                            "Scene '{}' pace_multiplier must be positive",
                            scene.id
                        )));
                    }
                }
                SceneKind::PinnedStory {
                    beats,
                    pace_multiplier,
                    ..
                } => {
                    if beats.is_empty() {
                        return Err(CoreError::Validation(format!(
                            "PinnedStory scene '{}' must have at least one beat",
                            scene.id
                        )));
                    }
                    if *pace_multiplier <= 0.0 {
                        return Err(CoreError::Validation(format!(
                            "Scene '{}' pace_multiplier must be positive",
                            scene.id
                        )));
                    }
                }
                _ => {}
            }
        }
        Ok(())
    }

    /// Collect deduplicated relative asset paths across all scenes.
    pub fn referenced_assets(&self) -> Vec<String> {
        let mut out = Vec::new();
        for scene in &self.scenes {
            for path in scene.referenced_assets() {
                if !out.contains(&path) {
                    out.push(path);
                }
            }
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::atmosphere::{Atmosphere, AudioCue, LightingMood};
    use crate::scene::{MediaItem, SpotlightFraming, StoryBeat};

    #[test]
    fn roundtrip_manifest_json() {
        let scenes = vec![
            Scene::new(
                Atmosphere::with_mood(LightingMood::WarmPaper),
                SceneKind::Cover {
                    title: "Autumn in Kyoto".into(),
                    subtitle: Some("Walk slowly through quiet streets".into()),
                    date_label: Some("2026.11".into()),
                    hero_image: Some(MediaItem {
                        src: "images/cover.jpg".into(),
                        alt: "Kyoto gate".into(),
                        caption: None,
                        meta: None,
                        width: Some(1200),
                        height: Some(1600),
                    }),
                    enter_label: "전시 입장하기".into(),
                },
            ),
            Scene::new(
                Atmosphere {
                    mood: LightingMood::DarkRoom,
                    audio: Some(AudioCue {
                        track: "audio/evening.wav".into(),
                        volume: 0.5,
                        fade_ms: 1500,
                        loop_audio: true,
                    }),
                    vignette: 0.4,
                },
                SceneKind::Spotlight {
                    chapter_label: Some("Room 01".into()),
                    title: Some("After Dusk".into()),
                    note: Some("Lanterns lit one by one.".into()),
                    media: MediaItem {
                        src: "images/01.jpg".into(),
                        alt: "Lantern".into(),
                        caption: Some("First lantern on the alley".into()),
                        meta: Some("2026.11.02 · 18:42".into()),
                        width: Some(1600),
                        height: Some(1067),
                    },
                    framing: SpotlightFraming::MuseumFrame,
                },
            ),
            Scene::new(
                Atmosphere::with_mood(LightingMood::Obsidian),
                SceneKind::PinnedStory {
                    chapter_label: Some("Interlude".into()),
                    beats: vec![StoryBeat {
                        eyebrow: Some("01".into()),
                        heading: Some("Stillness".into()),
                        body: "The rain stopped just before midnight.".into(),
                        media: None,
                    }],
                    pace_multiplier: 1.2,
                },
            ),
        ];

        let manifest = GalleryManifest::new("Autumn in Kyoto", scenes);
        let json = manifest.to_json_pretty().expect("serialize");
        let parsed = GalleryManifest::from_json_str(&json).expect("deserialize");

        assert_eq!(manifest, parsed);
        assert_eq!(
            parsed.referenced_assets(),
            vec!["images/cover.jpg", "audio/evening.wav", "images/01.jpg"]
        );
    }

    #[test]
    fn rejects_empty_scenes() {
        let manifest = GalleryManifest::new("Empty", vec![]);
        assert!(manifest.validate().is_err());
    }
}
