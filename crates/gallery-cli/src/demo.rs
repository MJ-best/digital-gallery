use std::f32::consts::TAU;
use std::fs;
use std::path::Path;

use gallery_core::{
    Atmosphere, AudioCue, GalleryManifest, LightingMood, MediaItem, Scene, SceneKind,
    SpotlightFraming, StoryBeat,
};
use gallery_export::export_exhibition;

/// Generate a self-contained sample `.gallery` package (artistic SVG photographs +
/// two synthesized ambient WAV soundscapes) and export it to HTML so the user can
/// immediately experience lighting transitions, horizontal scroll, pinned story,
/// and audio crossfading in Safari.
pub fn generate_demo(base_dir: &Path) -> Result<(), Box<dyn std::error::Error>> {
    let package_dir = base_dir.join("Quiet_Autumn.gallery");
    let images_dir = package_dir.join("images");
    let audio_dir = package_dir.join("audio");
    let export_dir = base_dir.join("export");

    fs::create_dir_all(&images_dir)?;
    fs::create_dir_all(&audio_dir)?;

    // 1. Write editorial sample SVG artworks (zero external dependencies).
    let artworks = [
        (
            "01_cover.svg",
            1200,
            1600,
            "#2B241E",
            "#C89D70",
            "#EFE6D8",
            "MORNING LIGHT",
            "07:14 AM · KYOTO",
        ),
        (
            "02_window.svg",
            1400,
            1000,
            "#D8CCB8",
            "#8A6B4A",
            "#26211D",
            "STILL WINDOW",
            "10:20 AM · 35MM",
        ),
        (
            "03_alley.svg",
            1600,
            1067,
            "#2D2622",
            "#B37B4C",
            "#F0E8DC",
            "AFTERNOON SHADOW",
            "15:40 PM · WALK I",
        ),
        (
            "04_bridge.svg",
            1600,
            1067,
            "#1F2428",
            "#7D9199",
            "#E9E6DF",
            "QUIET RIVER",
            "17:12 PM · WALK II",
        ),
        (
            "05_lantern.svg",
            1600,
            1067,
            "#191514",
            "#D99B52",
            "#F5ECE0",
            "FIRST LANTERN",
            "18:35 PM · WALK III",
        ),
        (
            "06_rain.svg",
            1600,
            1067,
            "#111418",
            "#6A8296",
            "#E6ECF0",
            "AFTER RAIN",
            "20:05 PM · WALK IV",
        ),
        (
            "07_night_01.svg",
            1200,
            1500,
            "#0E0E10",
            "#C99768",
            "#F2ECE1",
            "SILENCE I",
            "21:18 PM · DARK ROOM",
        ),
        (
            "08_night_02.svg",
            1200,
            1500,
            "#0B0C0E",
            "#96A8B8",
            "#ECEFF2",
            "SILENCE II",
            "22:04 PM · DARK ROOM",
        ),
    ];

    for (name, w, h, bg, accent, fg, title, meta) in artworks {
        let svg = build_editorial_svg(w, h, bg, accent, fg, title, meta);
        fs::write(images_dir.join(name), svg)?;
    }

    // 2. Synthesize two gentle, looping ambient WAV soundscapes (morning & night).
    write_ambient_wav(
        &audio_dir.join("morning_pad.wav"),
        6.0,
        &[220.0, 277.18, 329.63, 415.30], // A major 7th warm pad
        0.16,
    )?;
    write_ambient_wav(
        &audio_dir.join("night_drone.wav"),
        6.0,
        &[146.83, 220.0, 261.63, 329.63], // D minor 9th nocturnal room
        0.18,
    )?;

    // 3. Build a rich storyline manifest showcasing lighting, horizontal walk,
    //    pinned story beats, and crossfading audio.
    let morning_audio = AudioCue {
        track: "audio/morning_pad.wav".into(),
        volume: 0.45,
        fade_ms: 1400,
        loop_audio: true,
    };
    let night_audio = AudioCue {
        track: "audio/night_drone.wav".into(),
        volume: 0.50,
        fade_ms: 1600,
        loop_audio: true,
    };

    let scenes = vec![
        Scene::new(
            Atmosphere {
                mood: LightingMood::WarmPaper,
                audio: Some(morning_audio.clone()),
                vignette: 0.0,
            },
            SceneKind::Cover {
                title: "Quiet Autumn".into(),
                subtitle: Some("사진을 저장하는 것이 아니라, 발걸음과 빛으로 기억을 전시합니다.".into()),
                date_label: Some("2026.11.01 — 2026.11.03".into()),
                hero_image: Some(MediaItem {
                    src: "images/01_cover.svg".into(),
                    alt: "Morning light".into(),
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
                mood: LightingMood::WarmPaper,
                audio: Some(morning_audio),
                vignette: 0.0,
            },
            SceneKind::Spotlight {
                chapter_label: Some("Room 01 · Morning".into()),
                title: Some("창가로 스며든 첫 번째 빛".into()),
                note: Some(
                    "밝은 미색의 전시실에서 하루가 시작됩니다. 천천히 아래로 걸어 내려가 보세요."
                        .into(),
                ),
                media: MediaItem {
                    src: "images/02_window.svg".into(),
                    alt: "Still window".into(),
                    caption: Some("아직 아무도 깨지 않은 오전 열 시의 창가".into()),
                    meta: Some("2026.11.01 · 10:20 · 35mm".into()),
                    width: Some(1400),
                    height: Some(1000),
                },
                framing: SpotlightFraming::MuseumFrame,
            },
        ),
        Scene::new(
            Atmosphere {
                mood: LightingMood::DarkRoom,
                audio: Some(night_audio.clone()),
                vignette: 0.35,
            },
            SceneKind::HorizontalTrack {
                chapter_label: Some("Room 02 · Dusk Walk".into()),
                intro: Some(
                    "조명이 어두워지고 사운드가 바뀝니다. 아래로 스크롤하면 전시 벽면을 따라 옆으로 걸어갑니다."
                        .into(),
                ),
                items: vec![
                    MediaItem {
                        src: "images/03_alley.svg".into(),
                        alt: "Afternoon shadow".into(),
                        caption: Some("골목 끝으로 길게 늘어진 오후의 그림자".into()),
                        meta: Some("15:40 · Walk I".into()),
                        width: Some(1600),
                        height: Some(1067),
                    },
                    MediaItem {
                        src: "images/04_bridge.svg".into(),
                        alt: "Quiet river".into(),
                        caption: Some("강물 위로 해가 식어가는 순간".into()),
                        meta: Some("17:12 · Walk II".into()),
                        width: Some(1600),
                        height: Some(1067),
                    },
                    MediaItem {
                        src: "images/05_lantern.svg".into(),
                        alt: "First lantern".into(),
                        caption: Some("하나둘 켜지기 시작한 저녁의 등불".into()),
                        meta: Some("18:35 · Walk III".into()),
                        width: Some(1600),
                        height: Some(1067),
                    },
                    MediaItem {
                        src: "images/06_rain.svg".into(),
                        alt: "After rain".into(),
                        caption: Some("가벼운 비가 지나간 뒤 젖은 돌길".into()),
                        meta: Some("20:05 · Walk IV".into()),
                        width: Some(1600),
                        height: Some(1067),
                    },
                ],
                pace_multiplier: 1.15,
            },
        ),
        Scene::new(
            Atmosphere {
                mood: LightingMood::Obsidian,
                audio: Some(night_audio),
                vignette: 0.55,
            },
            SceneKind::PinnedStory {
                chapter_label: Some("Room 03 · Nocturne".into()),
                beats: vec![
                    StoryBeat {
                        eyebrow: Some("01 / 03".into()),
                        heading: Some("발걸음을 멈추는 공간".into()),
                        body: "화면이 고정된 채, 스크롤의 호흡에 맞춰 캡션과 사진이 천천히 교차합니다."
                            .into(),
                        media: Some(MediaItem {
                            src: "images/07_night_01.svg".into(),
                            alt: "Silence I".into(),
                            caption: None,
                            meta: None,
                            width: Some(1200),
                            height: Some(1500),
                        }),
                    },
                    StoryBeat {
                        eyebrow: Some("02 / 03".into()),
                        heading: Some("어둠 속에서 또렷해지는 기억".into()),
                        body: "주변 조명을 낮추고 비네팅을 깊게 주면, 관람객의 시선은 오직 하나의 장면과 문장에 머뭅니다."
                            .into(),
                        media: Some(MediaItem {
                            src: "images/08_night_02.svg".into(),
                            alt: "Silence II".into(),
                            caption: None,
                            meta: None,
                            width: Some(1200),
                            height: Some(1500),
                        }),
                    },
                    StoryBeat {
                        eyebrow: Some("03 / 03".into()),
                        heading: Some("그날의 온도를 남기다".into()),
                        body: "폴더 속 평범한 사진들도 동선과 빛, 소리가 더해지면 하나의 전시가 됩니다."
                            .into(),
                        media: None,
                    },
                ],
                pace_multiplier: 1.1,
            },
        ),
        Scene::new(
            Atmosphere::with_mood(LightingMood::WarmPaper),
            SceneKind::Ending {
                title: "Quiet Autumn".into(),
                message: Some("천천히 걸어주셔서 감사합니다.".into()),
                credits: vec![
                    "Digital Gallery · Prototype 01".into(),
                    "8 Artworks · 2 Ambient Soundscapes".into(),
                    "Generated by Rust Core + Tera".into(),
                ],
                replay_label: "처음으로 돌아가기".into(),
            },
        ),
    ];

    let mut manifest = GalleryManifest::new("Quiet Autumn", scenes);
    manifest.subtitle = Some("Prototype 01 Demo Exhibition".into());
    manifest.author = Some("Digital Gallery".into());

    let manifest_path = package_dir.join("manifest.json");
    manifest.save_to_path(&manifest_path)?;

    let report = export_exhibition(&manifest, &package_dir, &export_dir)?;
    println!("Created sample package: {}", package_dir.display());
    println!("Exported exhibition:    {}", report.output_html.display());
    println!("Copied {} asset(s).", report.copied_assets.len());

    Ok(())
}

fn build_editorial_svg(
    w: u32,
    h: u32,
    bg: &str,
    accent: &str,
    fg: &str,
    title: &str,
    meta: &str,
) -> String {
    let cx = w / 2;
    let cy = (h as f32 * 0.44) as u32;
    let r = (w.min(h) as f32 * 0.28) as u32;
    format!(
        r##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">
  <defs>
    <radialGradient id="g" cx="50%" cy="42%" r="65%">
      <stop offset="0%" stop-color="{accent}" stop-opacity="0.48"/>
      <stop offset="100%" stop-color="{bg}" stop-opacity="1"/>
    </radialGradient>
  </defs>
  <rect width="100%" height="100%" fill="{bg}"/>
  <rect width="100%" height="100%" fill="url(#g)"/>
  <circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="{fg}" stroke-opacity="0.22" stroke-width="1.5"/>
  <line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y1}" stroke="{accent}" stroke-opacity="0.6" stroke-width="1"/>
  <text x="50%" y="{ty}" text-anchor="middle" fill="{fg}" font-family="Georgia, serif" font-size="38" letter-spacing="8" opacity="0.9">{title}</text>
  <text x="50%" y="{my}" text-anchor="middle" fill="{fg}" font-family="-apple-system, sans-serif" font-size="16" letter-spacing="4" opacity="0.58">{meta}</text>
</svg>
"##,
        x1 = w / 4,
        x2 = (w * 3) / 4,
        y1 = (h as f32 * 0.72) as u32,
        ty = (h as f32 * 0.80) as u32,
        my = (h as f32 * 0.85) as u32,
    )
}

/// Synthesize a seamless, gentle looping PCM 16-bit mono WAV ambient pad.
fn write_ambient_wav(
    path: &Path,
    duration_secs: f32,
    freqs: &[f32],
    gain: f32,
) -> std::io::Result<()> {
    let sample_rate: u32 = 22_050;
    let num_samples = (duration_secs * sample_rate as f32) as usize;
    let mut pcm: Vec<u8> = Vec::with_capacity(num_samples * 2);

    for i in 0..num_samples {
        let t = i as f32 / sample_rate as f32;
        let phase_loop = t / duration_secs;
        // Smooth breathing envelope that loops cleanly at 0 and 1.
        let breath = 0.75 + 0.25 * (TAU * phase_loop).cos();

        let mut sample = 0.0f32;
        for (idx, &freq) in freqs.iter().enumerate() {
            // Snap frequency to integer cycles over duration_secs for clickless looping.
            let cycles = (freq * duration_secs).round();
            let snapped_freq = cycles / duration_secs;
            let weight = 1.0 / (idx as f32 + 1.2);
            sample += (TAU * snapped_freq * t).sin() * weight;
        }
        let norm = (sample / freqs.len() as f32) * gain * breath;
        let clamped = norm.clamp(-0.95, 0.95);
        let s16 = (clamped * i16::MAX as f32) as i16;
        pcm.extend_from_slice(&s16.to_le_bytes());
    }

    let data_size = pcm.len() as u32;
    let chunk_size = 36 + data_size;
    let byte_rate = sample_rate * 2;
    let mut wav = Vec::with_capacity(44 + pcm.len());
    wav.extend_from_slice(b"RIFF");
    wav.extend_from_slice(&chunk_size.to_le_bytes());
    wav.extend_from_slice(b"WAVE");
    wav.extend_from_slice(b"fmt ");
    wav.extend_from_slice(&16u32.to_le_bytes()); // PCM
    wav.extend_from_slice(&1u16.to_le_bytes()); // format = PCM
    wav.extend_from_slice(&1u16.to_le_bytes()); // mono
    wav.extend_from_slice(&sample_rate.to_le_bytes());
    wav.extend_from_slice(&byte_rate.to_le_bytes());
    wav.extend_from_slice(&2u16.to_le_bytes()); // block align
    wav.extend_from_slice(&16u16.to_le_bytes()); // bits per sample
    wav.extend_from_slice(b"data");
    wav.extend_from_slice(&data_size.to_le_bytes());
    wav.extend_from_slice(&pcm);

    fs::write(path, wav)
}
