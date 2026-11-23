pub mod atmosphere;
pub mod manifest;
pub mod scene;
pub mod theme;

pub use atmosphere::{Atmosphere, AudioCue, LightingMood, ResolvedPalette};
pub use manifest::{CURRENT_SCHEMA_VERSION, CoreError, GalleryManifest};
pub use scene::{MediaItem, Scene, SceneKind, SpotlightFraming, StoryBeat};
pub use theme::{ThemeConfig, ThemePreset};
