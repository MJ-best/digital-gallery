use serde::{Deserialize, Serialize};

/// Visual theme preset for the exported exhibition.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ThemePreset {
    /// Bright, lovable pastel sky & lavender UI with peeking cloud mascot,
    /// scalloped cloud cover wave, and warm sunset pill CTA ("Memoria" style).
    MemoriaPastel,
    /// Warm Paper <-> Dark Room editorial magazine (Riley & Grey / Magazine style).
    EditorialGallery,
    /// Darkroom film archive with amber accents & monospace EXIF stamps (Midnight Film style).
    MidnightFilm,
    /// Toss Simplicity clean white/slate cards, bold Pretendard hierarchy, 20px rounded rhythm.
    TossClean,
    /// Warm bone linen & espresso exhibition poster with double-hairline gallery framing.
    AtelierPoster,
}

impl Default for ThemePreset {
    fn default() -> Self {
        Self::MemoriaPastel
    }
}

impl ThemePreset {
    pub fn as_str(&self) -> &'static str {
        match self {
            ThemePreset::MemoriaPastel => "memoria_pastel",
            ThemePreset::EditorialGallery => "editorial_gallery",
            ThemePreset::MidnightFilm => "midnight_film",
            ThemePreset::TossClean => "toss_clean",
            ThemePreset::AtelierPoster => "atelier_poster",
        }
    }

    pub fn from_preset_str(s: &str) -> Option<Self> {
        match s {
            "memoria_pastel" => Some(Self::MemoriaPastel),
            "editorial_gallery" => Some(Self::EditorialGallery),
            "midnight_film" => Some(Self::MidnightFilm),
            "toss_clean" => Some(Self::TossClean),
            "atelier_poster" => Some(Self::AtelierPoster),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ThemeConfig {
    #[serde(default)]
    pub preset: ThemePreset,
    #[serde(default = "default_display_font")]
    pub display_font: String,
    #[serde(default = "default_body_font")]
    pub body_font: String,
    #[serde(default = "default_transition_ms")]
    pub lighting_transition_ms: u32,
}

fn default_display_font() -> String {
    "\"Iowan Old Style\", \"AppleMyungjo\", \"Noto Serif KR\", Georgia, serif".into()
}

fn default_body_font() -> String {
    "\"Pretendard\", -apple-system, BlinkMacSystemFont, \"Apple SD Gothic Neo\", sans-serif".into()
}

fn default_transition_ms() -> u32 {
    850
}

impl Default for ThemeConfig {
    fn default() -> Self {
        Self {
            preset: ThemePreset::MemoriaPastel,
            display_font: default_display_font(),
            body_font: default_body_font(),
            lighting_transition_ms: default_transition_ms(),
        }
    }
}
