use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::atmosphere::Atmosphere;

/// A single photo asset referenced by a scene.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MediaItem {
    /// Path relative to the manifest/project root (e.g. "images/01.jpg").
    pub src: String,
    /// Accessible description.
    #[serde(default)]
    pub alt: String,
    /// Optional exhibition caption displayed near the work.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub caption: Option<String>,
    /// Optional plaque metadata (e.g. "2026.05.12 · Jeju · 35mm").
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub meta: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub width: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub height: Option<u32>,
}

/// Framing style for a Spotlight scene.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SpotlightFraming {
    /// Generous museum matte margins around the artwork.
    MuseumFrame,
    /// Edge-to-edge immersive canvas.
    FullBleed,
    /// Editorial split with artwork and wall plaque.
    EditorialSplit,
}

impl Default for SpotlightFraming {
    fn default() -> Self {
        Self::MuseumFrame
    }
}

/// One sequential beat inside a `PinnedStory` scene.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct StoryBeat {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub eyebrow: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub heading: Option<String>,
    pub body: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub media: Option<MediaItem>,
}

/// The 6 core exhibition scene types for Prototype 01.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum SceneKind {
    /// Entrance cover that invites the visitor in and unlocks Safari Web Audio.
    Cover {
        title: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        subtitle: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        date_label: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        hero_image: Option<MediaItem>,
        #[serde(default = "default_enter_label")]
        enter_label: String,
    },

    /// A single featured artwork with optional wall plaque and framing.
    Spotlight {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        chapter_label: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        title: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        note: Option<String>,
        media: MediaItem,
        #[serde(default)]
        framing: SpotlightFraming,
    },

    /// Vertical scroll drives a sticky horizontal gallery walk, changing the
    /// viewer's spatial direction and pacing.
    HorizontalTrack {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        chapter_label: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        intro: Option<String>,
        items: Vec<MediaItem>,
        /// Multiplier for scroll runway length (1.0 = normal, >1.0 = slower, more deliberate).
        #[serde(default = "default_pace")]
        pace_multiplier: f32,
    },

    /// Sticky viewport that crossfades captions and photos as the visitor scrolls
    /// down a deliberate runway.
    PinnedStory {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        chapter_label: Option<String>,
        beats: Vec<StoryBeat>,
        #[serde(default = "default_pace")]
        pace_multiplier: f32,
    },

    /// Inline moving-image scene (muted autoplay loop by default for mobile Safari).
    VideoMoment {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        chapter_label: Option<String>,
        src: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        poster: Option<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        caption: Option<String>,
        #[serde(default = "default_true")]
        muted_autoplay: bool,
        #[serde(default = "default_true")]
        loop_video: bool,
    },

    /// Closing room with final note, credits, and return-to-top action.
    Ending {
        title: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        message: Option<String>,
        #[serde(default)]
        credits: Vec<String>,
        #[serde(default = "default_replay_label")]
        replay_label: String,
    },
}

fn default_enter_label() -> String {
    "전시 입장하기".into()
}

fn default_replay_label() -> String {
    "처음으로 돌아가기".into()
}

fn default_pace() -> f32 {
    1.0
}

fn default_true() -> bool {
    true
}

/// A single room/moment in the exhibition storyline.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Scene {
    #[serde(default = "new_scene_id")]
    pub id: String,
    #[serde(default)]
    pub atmosphere: Atmosphere,
    #[serde(flatten)]
    pub kind: SceneKind,
}

fn new_scene_id() -> String {
    format!("scene-{}", &Uuid::new_v4().to_string()[..8])
}

impl Scene {
    pub fn new(atmosphere: Atmosphere, kind: SceneKind) -> Self {
        Self {
            id: new_scene_id(),
            atmosphere,
            kind,
        }
    }

    /// Collect all relative media asset paths referenced by this scene.
    pub fn referenced_assets(&self) -> Vec<String> {
        let mut paths = Vec::new();
        if let Some(audio) = &self.atmosphere.audio {
            paths.push(audio.track.clone());
        }
        match &self.kind {
            SceneKind::Cover { hero_image, .. } => {
                if let Some(img) = hero_image {
                    paths.push(img.src.clone());
                }
            }
            SceneKind::Spotlight { media, .. } => {
                paths.push(media.src.clone());
            }
            SceneKind::HorizontalTrack { items, .. } => {
                for item in items {
                    paths.push(item.src.clone());
                }
            }
            SceneKind::PinnedStory { beats, .. } => {
                for beat in beats {
                    if let Some(media) = &beat.media {
                        paths.push(media.src.clone());
                    }
                }
            }
            SceneKind::VideoMoment { src, poster, .. } => {
                paths.push(src.clone());
                if let Some(p) = poster {
                    paths.push(p.clone());
                }
            }
            SceneKind::Ending { .. } => {}
        }
        paths
    }
}
