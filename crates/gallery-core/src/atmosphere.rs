use serde::{Deserialize, Serialize};

/// Lighting mood for a scene. The exhibition runtime smoothly transitions
/// CSS variables (background, foreground, muted text, accent) as the viewer
/// walks from one scene into the next.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "preset", rename_all = "snake_case")]
pub enum LightingMood {
    /// Warm gallery paper (#F6F2EB) with deep charcoal ink (#1E1C1A).
    WarmPaper,
    /// Soft afternoon dim (#EAE3D6) for transitional moments.
    SoftDim,
    /// Dark exhibition room (#171615) with warm ivory ink (#F2EDE4).
    DarkRoom,
    /// Deep obsidian (#0B0B0C) for cinema / climax spotlight moments.
    Obsidian,
    /// Custom palette for author-defined lighting.
    Custom {
        background: String,
        foreground: String,
        muted: String,
        accent: String,
    },
}

impl Default for LightingMood {
    fn default() -> Self {
        Self::WarmPaper
    }
}

/// Resolved CSS color values for a lighting mood.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ResolvedPalette {
    pub background: String,
    pub surface: String,
    pub foreground: String,
    pub muted: String,
    pub accent: String,
    pub border: String,
    pub is_dark: bool,
}

impl LightingMood {
    pub fn resolve(&self) -> ResolvedPalette {
        match self {
            LightingMood::WarmPaper => ResolvedPalette {
                background: "#F6F2EB".into(),
                surface: "#EFE9DF".into(),
                foreground: "#1E1C1A".into(),
                muted: "#6F675E".into(),
                accent: "#9C6B43".into(),
                border: "rgba(30, 28, 26, 0.12)".into(),
                is_dark: false,
            },
            LightingMood::SoftDim => ResolvedPalette {
                background: "#E7DFD2".into(),
                surface: "#DDD3C2".into(),
                foreground: "#1C1A17".into(),
                muted: "#625A50".into(),
                accent: "#8A5A36".into(),
                border: "rgba(28, 26, 23, 0.14)".into(),
                is_dark: false,
            },
            LightingMood::DarkRoom => ResolvedPalette {
                background: "#171615".into(),
                surface: "#22201E".into(),
                foreground: "#F2EDE4".into(),
                muted: "#A49B8E".into(),
                accent: "#D2A679".into(),
                border: "rgba(242, 237, 228, 0.14)".into(),
                is_dark: true,
            },
            LightingMood::Obsidian => ResolvedPalette {
                background: "#0B0B0C".into(),
                surface: "#151518".into(),
                foreground: "#F7F4EE".into(),
                muted: "#958F86".into(),
                accent: "#E0B98C".into(),
                border: "rgba(247, 244, 238, 0.12)".into(),
                is_dark: true,
            },
            LightingMood::Custom {
                background,
                foreground,
                muted,
                accent,
            } => ResolvedPalette {
                background: background.clone(),
                surface: background.clone(),
                foreground: foreground.clone(),
                muted: muted.clone(),
                accent: accent.clone(),
                border: "rgba(128, 128, 128, 0.2)".into(),
                is_dark: false,
            },
        }
    }
}

/// Ambient audio or BGM cue triggered when entering a scene.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AudioCue {
    /// Relative asset path (e.g. "audio/morning.wav" or "audio/rain.mp3").
    pub track: String,
    /// Target playback volume in 0.0..=1.0.
    #[serde(default = "default_volume")]
    pub volume: f32,
    /// Crossfade duration in milliseconds.
    #[serde(default = "default_fade_ms")]
    pub fade_ms: u32,
    /// Loop continuously while active.
    #[serde(default = "default_true")]
    pub loop_audio: bool,
}

fn default_volume() -> f32 {
    0.55
}

fn default_fade_ms() -> u32 {
    1200
}

fn default_true() -> bool {
    true
}

/// Environmental atmosphere attached to every scene: lighting mood,
/// optional ambient audio cue, and vignette depth.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Atmosphere {
    #[serde(default)]
    pub mood: LightingMood,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub audio: Option<AudioCue>,
    /// Subtle edge darkening (0.0 = none, 1.0 = strong spotlight vignette).
    #[serde(default)]
    pub vignette: f32,
}

impl Default for Atmosphere {
    fn default() -> Self {
        Self {
            mood: LightingMood::WarmPaper,
            audio: None,
            vignette: 0.0,
        }
    }
}

impl Atmosphere {
    pub fn with_mood(mood: LightingMood) -> Self {
        let vignette = match mood {
            LightingMood::DarkRoom => 0.35,
            LightingMood::Obsidian => 0.55,
            _ => 0.0,
        };
        Self {
            mood,
            audio: None,
            vignette,
        }
    }
}
