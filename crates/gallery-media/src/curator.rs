use chrono::{Duration, NaiveDateTime, Timelike};
use gallery_core::{
    Atmosphere, AudioCue, GalleryManifest, LightingMood, MediaItem, Scene, SceneKind,
    SpotlightFraming, StoryBeat,
};

use crate::scanner::{MediaKind, Orientation, ScannedAsset};

/// Options controlling automatic EXIF-based chapter clustering and scene curation.
#[derive(Debug, Clone)]
pub struct CurateOptions {
    pub title: String,
    pub subtitle: Option<String>,
    pub author: Option<String>,
    /// Start a new exhibition chapter whenever consecutive photos are farther
    /// apart than this gap (default: 4 hours).
    pub chapter_gap_hours: i64,
}

impl Default for CurateOptions {
    fn default() -> Self {
        Self {
            title: "Untitled Exhibition".into(),
            subtitle: Some("Curated from your photo archive".into()),
            author: None,
            chapter_gap_hours: 4,
        }
    }
}

/// A chronologically clustered group of visual assets (images & videos).
#[derive(Debug, Clone)]
pub struct MediaChapter {
    pub index: usize,
    pub label: String,
    pub start_time: Option<NaiveDateTime>,
    pub assets: Vec<ScannedAsset>,
}

/// Cluster visual assets into chapters by EXIF/file timestamps.
pub fn cluster_by_time(assets: &[ScannedAsset], gap_hours: i64) -> Vec<MediaChapter> {
    let visual: Vec<ScannedAsset> = assets
        .iter()
        .filter(|a| matches!(a.kind, MediaKind::Image | MediaKind::Video))
        .cloned()
        .collect();

    if visual.is_empty() {
        return Vec::new();
    }

    let gap = Duration::hours(gap_hours.max(1));
    let mut chapters: Vec<Vec<ScannedAsset>> = Vec::new();

    for asset in visual {
        let should_split = match chapters.last().and_then(|c| c.last()) {
            None => true,
            Some(prev) => match (prev.taken_at, asset.taken_at) {
                (Some(t1), Some(t2)) => {
                    let diff = t2.signed_duration_since(t1);
                    diff >= gap || (t1.date() != t2.date() && diff >= Duration::hours(2))
                }
                _ => false,
            },
        };

        if should_split {
            chapters.push(vec![asset]);
        } else if let Some(last) = chapters.last_mut() {
            last.push(asset);
        }
    }

    chapters
        .into_iter()
        .enumerate()
        .map(|(idx, group)| {
            let start_time = group.first().and_then(|a| a.taken_at);
            let label = match start_time {
                Some(dt) => format!("Chapter {:02} · {}", idx + 1, dt.format("%Y.%m.%d")),
                None => format!("Chapter {:02}", idx + 1),
            };
            MediaChapter {
                index: idx,
                label,
                start_time,
                assets: group,
            }
        })
        .collect()
}

/// Automatically curate a `GalleryManifest` draft from scanned media assets:
/// - Picks a hero cover image
/// - Clusters photos/videos into time-based chapters
/// - Recommends lighting mood by time of day (morning warm paper -> dusk dim -> night dark room)
/// - Recommends scenes by aspect ratio & sequence length (Spotlight, HorizontalTrack, PinnedStory, VideoMoment)
/// - Attaches discovered audio files as crossfading `AudioCue`s
pub fn curate_manifest(assets: &[ScannedAsset], options: CurateOptions) -> GalleryManifest {
    let audio_tracks: Vec<&ScannedAsset> = assets
        .iter()
        .filter(|a| a.kind == MediaKind::Audio)
        .collect();
    let chapters = cluster_by_time(assets, options.chapter_gap_hours);

    let mut scenes: Vec<Scene> = Vec::new();

    // 1. Cover scene: prefer first portrait or first image overall.
    let first_image = assets
        .iter()
        .find(|a| a.kind == MediaKind::Image && a.orientation() == Orientation::Portrait)
        .or_else(|| assets.iter().find(|a| a.kind == MediaKind::Image));

    let date_label = build_date_range_label(assets);

    let mut cover_atmosphere = Atmosphere::with_mood(LightingMood::WarmPaper);
    if let Some(track) = audio_tracks.first() {
        cover_atmosphere.audio = Some(AudioCue {
            track: track.relative_path.clone(),
            volume: 0.45,
            fade_ms: 1400,
            loop_audio: true,
        });
    }

    scenes.push(Scene::new(
        cover_atmosphere,
        SceneKind::Cover {
            title: options.title.clone(),
            subtitle: options.subtitle.clone(),
            date_label: date_label.clone(),
            hero_image: first_image.map(to_media_item),
            enter_label: "전시 입장하기".into(),
        },
    ));

    // 2. Curate each chapter into expressive exhibition scenes.
    for chapter in &chapters {
        let base_mood = infer_chapter_mood(chapter);
        let chapter_audio = if audio_tracks.len() > 1 {
            let track = audio_tracks[chapter.index % audio_tracks.len()];
            Some(AudioCue {
                track: track.relative_path.clone(),
                volume: 0.5,
                fade_ms: 1400,
                loop_audio: true,
            })
        } else {
            None
        };

        let mut photo_buffer: Vec<ScannedAsset> = Vec::new();
        let mut chapter_labeled = false;

        for asset in &chapter.assets {
            if asset.kind == MediaKind::Video {
                flush_photo_buffer(
                    &mut photo_buffer,
                    &chapter.label,
                    &mut chapter_labeled,
                    &base_mood,
                    &chapter_audio,
                    &mut scenes,
                );
                let mut atmo = Atmosphere::with_mood(LightingMood::DarkRoom);
                atmo.audio = chapter_audio.clone();
                scenes.push(Scene::new(
                    atmo,
                    SceneKind::VideoMoment {
                        chapter_label: if !chapter_labeled {
                            chapter_labeled = true;
                            Some(chapter.label.clone())
                        } else {
                            None
                        },
                        src: asset.relative_path.clone(),
                        poster: None,
                        caption: Some(humanize_filename(&asset.filename)),
                        muted_autoplay: true,
                        loop_video: true,
                    },
                ));
            } else {
                photo_buffer.push(asset.clone());
            }
        }

        flush_photo_buffer(
            &mut photo_buffer,
            &chapter.label,
            &mut chapter_labeled,
            &base_mood,
            &chapter_audio,
            &mut scenes,
        );
    }

    // 3. Ending scene.
    let photo_count = assets.iter().filter(|a| a.kind == MediaKind::Image).count();
    let video_count = assets.iter().filter(|a| a.kind == MediaKind::Video).count();
    let mut credits = vec![format!("{photo_count} Photos · {video_count} Videos")];
    if let Some(range) = date_label {
        credits.push(range);
    }
    if let Some(author) = &options.author {
        credits.push(format!("Curated by {author}"));
    }

    scenes.push(Scene::new(
        Atmosphere::with_mood(LightingMood::DarkRoom),
        SceneKind::Ending {
            title: options.title.clone(),
            message: Some("천천히 걸어주셔서 감사합니다.".into()),
            credits,
            replay_label: "처음으로 돌아가기".into(),
        },
    ));

    let mut manifest = GalleryManifest::new(options.title, scenes);
    manifest.subtitle = options.subtitle;
    manifest.author = options.author;
    manifest
}

fn flush_photo_buffer(
    buffer: &mut Vec<ScannedAsset>,
    chapter_label: &str,
    chapter_labeled: &mut bool,
    base_mood: &LightingMood,
    chapter_audio: &Option<AudioCue>,
    scenes: &mut Vec<Scene>,
) {
    if buffer.is_empty() {
        return;
    }

    let items = std::mem::take(buffer);
    let mut take_label = || {
        if !*chapter_labeled {
            *chapter_labeled = true;
            Some(chapter_label.to_string())
        } else {
            None
        }
    };

    let make_atmo = |mood: LightingMood| {
        let mut a = Atmosphere::with_mood(mood);
        a.audio = chapter_audio.clone();
        a
    };

    // Single photo -> Spotlight (FullBleed for panorama/portrait, MuseumFrame otherwise).
    if items.len() == 1 {
        let a = &items[0];
        let framing = match a.orientation() {
            Orientation::Panorama => SpotlightFraming::FullBleed,
            Orientation::Portrait => SpotlightFraming::EditorialSplit,
            _ => SpotlightFraming::MuseumFrame,
        };
        scenes.push(Scene::new(
            make_atmo(base_mood.clone()),
            SceneKind::Spotlight {
                chapter_label: take_label(),
                title: Some(humanize_filename(&a.filename)),
                note: None,
                media: to_media_item(a),
                framing,
            },
        ));
        return;
    }

    // 2 photos -> PinnedStory (contemplative crossfading narrative beats).
    if items.len() == 2 {
        let beats = items
            .iter()
            .enumerate()
            .map(|(i, a)| StoryBeat {
                eyebrow: Some(format!("{:02}", i + 1)),
                heading: Some(humanize_filename(&a.filename)),
                body: a
                    .plaque_meta()
                    .unwrap_or_else(|| "이 순간의 기억을 캡션으로 남겨보세요.".into()),
                media: Some(to_media_item(a)),
            })
            .collect();

        let mood = match base_mood {
            LightingMood::WarmPaper => LightingMood::SoftDim,
            other => other.clone(),
        };
        scenes.push(Scene::new(
            make_atmo(mood),
            SceneKind::PinnedStory {
                chapter_label: take_label(),
                beats,
                pace_multiplier: 1.15,
            },
        ));
        return;
    }

    // 3+ photos -> Lead with a Spotlight if the first is portrait/panorama,
    // then walk horizontally through the rest (`HorizontalTrack`).
    let mut slice_start = 0;
    if items.len() >= 4
        && matches!(
            items[0].orientation(),
            Orientation::Portrait | Orientation::Panorama
        )
    {
        let lead = &items[0];
        scenes.push(Scene::new(
            make_atmo(base_mood.clone()),
            SceneKind::Spotlight {
                chapter_label: take_label(),
                title: Some(humanize_filename(&lead.filename)),
                note: None,
                media: to_media_item(lead),
                framing: SpotlightFraming::MuseumFrame,
            },
        ));
        slice_start = 1;
    }

    let track_items: Vec<MediaItem> = items[slice_start..].iter().map(to_media_item).collect();
    let track_mood = match base_mood {
        LightingMood::WarmPaper => LightingMood::DarkRoom,
        other => other.clone(),
    };
    scenes.push(Scene::new(
        make_atmo(track_mood),
        SceneKind::HorizontalTrack {
            chapter_label: take_label(),
            intro: Some("스크롤을 내려 옆으로 걸으며 감상해 보세요.".into()),
            items: track_items,
            pace_multiplier: 1.1,
        },
    ));
}

fn infer_chapter_mood(chapter: &MediaChapter) -> LightingMood {
    let hours: Vec<u32> = chapter
        .assets
        .iter()
        .filter_map(|a| a.taken_at.map(|dt| dt.hour()))
        .collect();

    if !hours.is_empty() {
        let avg_hour = hours.iter().sum::<u32>() / hours.len() as u32;
        return match avg_hour {
            6..=15 => LightingMood::WarmPaper,
            16..=19 => LightingMood::SoftDim,
            _ => LightingMood::DarkRoom,
        };
    }

    // Fallback rhythm when no timestamps exist.
    match chapter.index % 3 {
        0 => LightingMood::WarmPaper,
        1 => LightingMood::DarkRoom,
        _ => LightingMood::SoftDim,
    }
}

fn build_date_range_label(assets: &[ScannedAsset]) -> Option<String> {
    let times: Vec<NaiveDateTime> = assets.iter().filter_map(|a| a.taken_at).collect();
    let first = times.first()?;
    let last = times.last()?;
    if first.date() == last.date() {
        Some(first.format("%Y.%m.%d").to_string())
    } else {
        Some(format!(
            "{} — {}",
            first.format("%Y.%m.%d"),
            last.format("%Y.%m.%d")
        ))
    }
}

fn to_media_item(asset: &ScannedAsset) -> MediaItem {
    let clean_name = clean_display_name(&asset.filename);
    MediaItem {
        src: asset.relative_path.clone(),
        alt: clean_name.clone().unwrap_or_else(|| "Exhibition photograph".into()),
        caption: clean_name,
        meta: asset.plaque_meta(),
        width: asset.width,
        height: asset.height,
    }
}

fn humanize_filename(stem: &str) -> String {
    clean_display_name(stem).unwrap_or_else(|| "Untitled Moment".into())
}

/// Filter out raw camera filenames (IMG_4821, DSC_0012, PXL_2026..., Screenshot...)
/// so auto-curated drafts don't pollute the exhibition with robotic captions.
fn clean_display_name(stem: &str) -> Option<String> {
    let upper = stem.to_ascii_uppercase();
    let is_camera_generated = upper.starts_with("IMG_")
        || upper.starts_with("DSC_")
        || upper.starts_with("DSC0")
        || upper.starts_with("PXL_")
        || upper.starts_with("MVIMG_")
        || upper.starts_with("DCIM")
        || upper.starts_with("PHOTO_")
        || upper.chars().all(|c| c.is_ascii_digit() || c == '_' || c == '-');
    if is_camera_generated {
        return None;
    }
    let cleaned = stem.replace(['_', '-'], " ").trim().to_string();
    if cleaned.is_empty() {
        None
    } else {
        Some(cleaned)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn photo(name: &str, w: u32, h: u32, dt: &str) -> ScannedAsset {
        ScannedAsset {
            relative_path: format!("photos/{name}.jpg"),
            filename: name.into(),
            kind: MediaKind::Image,
            width: Some(w),
            height: Some(h),
            taken_at: NaiveDateTime::parse_from_str(dt, "%Y-%m-%d %H:%M:%S").ok(),
            camera_model: Some("iPhone 16 Pro".into()),
        }
    }

    #[test]
    fn clusters_by_time_gap_and_recommends_scenes() {
        let assets = vec![
            // Morning cluster (1 photo -> Spotlight)
            photo("01_morning_coffee", 1200, 1600, "2026-11-01 09:10:00"),
            // Evening cluster (4 photos -> Spotlight + HorizontalTrack)
            photo("02_sunset_gate", 1200, 1600, "2026-11-01 20:05:00"),
            photo("03_lantern_walk", 1600, 1067, "2026-11-01 20:15:00"),
            photo("04_river_reflection", 1600, 1067, "2026-11-01 20:22:00"),
            photo("05_quiet_alley", 1600, 1067, "2026-11-01 20:30:00"),
            // Audio file
            ScannedAsset {
                relative_path: "audio/ambient.wav".into(),
                filename: "ambient".into(),
                kind: MediaKind::Audio,
                width: None,
                height: None,
                taken_at: None,
                camera_model: None,
            },
        ];

        let chapters = cluster_by_time(&assets, 4);
        assert_eq!(chapters.len(), 2);

        let manifest = curate_manifest(
            &assets,
            CurateOptions {
                title: "Kyoto Walk".into(),
                ..Default::default()
            },
        );
        manifest.validate().expect("curated manifest should be valid");

        // Cover + Ch1 Spotlight + Ch2 Spotlight + Ch2 HorizontalTrack + Ending = 5 scenes
        assert_eq!(manifest.scenes.len(), 5);
        assert!(matches!(manifest.scenes[0].kind, SceneKind::Cover { .. }));
        assert!(matches!(manifest.scenes[1].kind, SceneKind::Spotlight { .. }));
        assert!(matches!(manifest.scenes[3].kind, SceneKind::HorizontalTrack { .. }));
        assert!(matches!(manifest.scenes[4].kind, SceneKind::Ending { .. }));
        assert_eq!(manifest.scenes[1].atmosphere.mood, LightingMood::WarmPaper);
        assert_eq!(manifest.scenes[2].atmosphere.mood, LightingMood::DarkRoom);
    }
}
