use gallery_core::ThemeConfig;

/// Generate the Editorial Gallery CSS stylesheet with dynamic lighting tokens
/// and mobile-first responsive exhibition layouts.
pub fn render_stylesheet(theme: &ThemeConfig) -> String {
    format!(
        r#"/* Digital Gallery — Editorial Gallery Theme */
:root {{
  --bg: #F6F2EB;
  --surface: #EFE9DF;
  --fg: #1E1C1A;
  --muted: #6F675E;
  --accent: #9C6B43;
  --border: rgba(30, 28, 26, 0.12);
  --vignette: 0;
  --font-display: {display_font};
  --font-body: {body_font};
  --light-ms: {transition_ms}ms;
  --ease-editorial: cubic-bezier(0.22, 1, 0.36, 1);
}}

*, *::before, *::after {{
  box-sizing: border-box;
  margin: 0;
  padding: 0;
}}

html {{
  scroll-behavior: smooth;
  -webkit-text-size-adjust: 100%;
  background: var(--bg);
}}

body {{
  font-family: var(--font-body);
  background-color: var(--bg);
  color: var(--fg);
  line-height: 1.65;
  overflow-x: clip;
  transition:
    background-color var(--light-ms) var(--ease-editorial),
    color var(--light-ms) var(--ease-editorial);
}}

img, video {{
  display: block;
  max-width: 100%;
}}

/* Ambient vignette layer for dimmed exhibition rooms */
#vignette-layer {{
  position: fixed;
  inset: 0;
  pointer-events: none;
  z-index: 40;
  background: radial-gradient(
    ellipse at center,
    rgba(0, 0, 0, 0) 42%,
    rgba(0, 0, 0, 0.72) 100%
  );
  opacity: var(--vignette);
  transition: opacity var(--light-ms) var(--ease-editorial);
}}

/* Top hairline progress bar */
#progress-bar {{
  position: fixed;
  top: 0;
  left: 0;
  height: 2px;
  width: 100%;
  transform-origin: left center;
  transform: scaleX(0);
  background: var(--accent);
  z-index: 60;
  opacity: 0.85;
}}

/* Floating audio & exhibition HUD */
.hud-controls {{
  position: fixed;
  top: max(16px, env(safe-area-inset-top));
  right: max(16px, env(safe-area-inset-right));
  z-index: 70;
  display: flex;
  align-items: center;
  gap: 8px;
}}

.audio-toggle {{
  appearance: none;
  border: 1px solid var(--border);
  background: color-mix(in srgb, var(--bg) 78%, transparent);
  backdrop-filter: blur(12px);
  -webkit-backdrop-filter: blur(12px);
  color: var(--fg);
  font-family: var(--font-body);
  font-size: 12px;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  padding: 8px 14px;
  border-radius: 999px;
  cursor: pointer;
  display: inline-flex;
  align-items: center;
  gap: 8px;
  transition:
    background-color var(--light-ms) var(--ease-editorial),
    color var(--light-ms) var(--ease-editorial),
    border-color var(--light-ms) var(--ease-editorial),
    transform 200ms ease;
}}

.audio-toggle:active {{
  transform: scale(0.96);
}}

.audio-dot {{
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--muted);
  transition: background-color 300ms ease, box-shadow 300ms ease;
}}

.audio-toggle[data-playing="true"] .audio-dot {{
  background: var(--accent);
  box-shadow: 0 0 10px var(--accent);
}}

/* Shared typography & museum plaques */
.chapter-label {{
  font-size: 11px;
  letter-spacing: 0.22em;
  text-transform: uppercase;
  color: var(--accent);
  margin-bottom: 12px;
  display: block;
}}

.display-title {{
  font-family: var(--font-display);
  font-weight: 400;
  letter-spacing: -0.02em;
  line-height: 1.18;
}}

.plaque {{
  margin-top: 16px;
  padding-top: 12px;
  border-top: 1px solid var(--border);
  transition: border-color var(--light-ms) var(--ease-editorial);
}}

.plaque-caption {{
  font-size: 14px;
  color: var(--fg);
  line-height: 1.55;
}}

.plaque-meta {{
  margin-top: 4px;
  font-size: 11px;
  letter-spacing: 0.08em;
  color: var(--muted);
}}

/* Scroll reveal animation */
.reveal {{
  opacity: 0;
  transform: translateY(22px);
  transition:
    opacity 900ms var(--ease-editorial),
    transform 900ms var(--ease-editorial);
}}

.reveal.is-visible {{
  opacity: 1;
  transform: translateY(0);
}}

/* =========================================================
   1. COVER SCENE (Entrance)
   ========================================================= */
.scene-cover {{
  position: relative;
  min-height: 100svh;
  display: flex;
  flex-direction: column;
  justify-content: flex-end;
  padding: 48px 24px max(48px, env(safe-area-inset-bottom));
  overflow: hidden;
}}

.cover-backdrop {{
  position: absolute;
  inset: 0;
  z-index: 0;
}}

.cover-backdrop img {{
  width: 100%;
  height: 100%;
  object-fit: cover;
  filter: brightness(0.74) saturate(0.92);
  transform: scale(1.03);
}}

.cover-scrim {{
  position: absolute;
  inset: 0;
  background: linear-gradient(
    to top,
    rgba(16, 15, 14, 0.86) 0%,
    rgba(16, 15, 14, 0.34) 48%,
    rgba(16, 15, 14, 0.14) 100%
  );
}}

.cover-content {{
  position: relative;
  z-index: 2;
  max-width: 680px;
  margin: 0 auto;
  width: 100%;
  text-align: center;
}}

.scene-cover.has-hero .cover-content {{
  color: #F6F2EB;
}}

.cover-date {{
  font-size: 12px;
  letter-spacing: 0.24em;
  text-transform: uppercase;
  opacity: 0.78;
  margin-bottom: 14px;
}}

.cover-title {{
  font-size: clamp(2.1rem, 8vw, 4.2rem);
  margin-bottom: 14px;
}}

.cover-subtitle {{
  font-size: clamp(0.95rem, 3.2vw, 1.15rem);
  opacity: 0.84;
  max-width: 44ch;
  margin: 0 auto 32px;
}}

.enter-btn {{
  appearance: none;
  border: 1px solid currentColor;
  background: rgba(255, 255, 255, 0.08);
  backdrop-filter: blur(8px);
  -webkit-backdrop-filter: blur(8px);
  color: inherit;
  font-family: var(--font-body);
  font-size: 13px;
  letter-spacing: 0.16em;
  padding: 14px 32px;
  border-radius: 999px;
  cursor: pointer;
  transition: background-color 260ms ease, transform 260ms ease;
}}

.enter-btn:hover {{
  background: rgba(255, 255, 255, 0.18);
}}

.enter-btn:active {{
  transform: scale(0.97);
}}

.cover-hint {{
  margin-top: 18px;
  font-size: 11px;
  letter-spacing: 0.12em;
  opacity: 0.62;
}}

/* =========================================================
   2. SPOTLIGHT SCENE (Single Featured Work)
   ========================================================= */
.scene-spotlight {{
  min-height: 100svh;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 88px 20px;
}}

.spotlight-inner {{
  width: 100%;
  max-width: 960px;
  margin: 0 auto;
}}

.spotlight-header {{
  margin-bottom: 28px;
  max-width: 560px;
}}

.spotlight-title {{
  font-size: clamp(1.5rem, 5vw, 2.4rem);
  margin-bottom: 10px;
}}

.spotlight-note {{
  font-size: 15px;
  color: var(--muted);
}}

.spotlight-frame {{
  background: var(--surface);
  padding: clamp(12px, 3vw, 28px);
  border: 1px solid var(--border);
  box-shadow: 0 24px 60px rgba(0, 0, 0, 0.12);
  transition:
    background-color var(--light-ms) var(--ease-editorial),
    border-color var(--light-ms) var(--ease-editorial);
}}

.spotlight-frame img {{
  width: 100%;
  max-height: 72svh;
  object-fit: contain;
  margin: 0 auto;
}}

/* FullBleed variant */
.scene-spotlight.framing-full_bleed {{
  padding: 0;
  position: relative;
}}

.scene-spotlight.framing-full_bleed .spotlight-inner {{
  max-width: none;
  position: relative;
  min-height: 100svh;
  display: flex;
  flex-direction: column;
  justify-content: flex-end;
}}

.scene-spotlight.framing-full_bleed .fullbleed-media {{
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  object-fit: cover;
}}

.scene-spotlight.framing-full_bleed .fullbleed-overlay {{
  position: relative;
  z-index: 2;
  padding: 72px 24px 48px;
  background: linear-gradient(to top, rgba(10, 10, 10, 0.78), rgba(10, 10, 10, 0));
  color: #F6F2EB;
}}

/* EditorialSplit variant */
.scene-spotlight.framing-editorial_split .split-grid {{
  display: grid;
  grid-template-columns: 1fr;
  gap: 28px;
  align-items: center;
}}

@media (min-width: 820px) {{
  .scene-spotlight.framing-editorial_split .split-grid {{
    grid-template-columns: 1.2fr 0.8fr;
    gap: 48px;
  }}
}}

/* =========================================================
   3. HORIZONTAL TRACK SCENE (Sticky Vertical -> Horizontal)
   ========================================================= */
.scene-horizontal {{
  position: relative;
}}

.horizontal-sticky {{
  position: sticky;
  top: 0;
  height: 100svh;
  overflow: hidden;
  display: flex;
  flex-direction: column;
  justify-content: center;
  padding: 64px 0 36px;
}}

.horizontal-header {{
  padding: 0 24px;
  margin-bottom: 20px;
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 16px;
}}

.horizontal-intro {{
  font-size: 14px;
  color: var(--muted);
  max-width: 38ch;
}}

.horizontal-cue {{
  font-size: 11px;
  letter-spacing: 0.16em;
  color: var(--accent);
  white-space: nowrap;
}}

.horizontal-rail {{
  display: flex;
  align-items: center;
  gap: clamp(20px, 4vw, 48px);
  padding: 0 24px 0 24px;
  will-change: transform;
}}

.track-card {{
  flex: 0 0 auto;
  width: min(82vw, 560px);
}}

.track-card-frame {{
  background: var(--surface);
  border: 1px solid var(--border);
  padding: 10px;
  box-shadow: 0 18px 44px rgba(0, 0, 0, 0.14);
}}

.track-card-frame img {{
  width: 100%;
  height: min(56svh, 460px);
  object-fit: cover;
}}

.horizontal-meter {{
  margin: 22px 24px 0;
  height: 2px;
  background: var(--border);
  overflow: hidden;
}}

.horizontal-meter-fill {{
  height: 100%;
  width: 100%;
  background: var(--accent);
  transform-origin: left center;
  transform: scaleX(0);
}}

/* =========================================================
   4. PINNED STORY SCENE (Sticky Crossfading Narrative Beats)
   ========================================================= */
.scene-pinned {{
  position: relative;
}}

.pinned-sticky {{
  position: sticky;
  top: 0;
  height: 100svh;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 64px 24px 48px;
  overflow: hidden;
}}

.pinned-stage {{
  position: relative;
  width: 100%;
  max-width: 880px;
  height: min(76svh, 640px);
}}

.pinned-beat {{
  position: absolute;
  inset: 0;
  display: grid;
  grid-template-columns: 1fr;
  gap: 20px;
  align-content: center;
  opacity: 0;
  transform: translateY(18px);
  pointer-events: none;
  transition:
    opacity 650ms var(--ease-editorial),
    transform 650ms var(--ease-editorial);
}}

.pinned-beat.is-active {{
  opacity: 1;
  transform: translateY(0);
  pointer-events: auto;
}}

.pinned-beat-media {{
  width: 100%;
  max-height: 44svh;
  object-fit: cover;
  border: 1px solid var(--border);
  box-shadow: 0 20px 50px rgba(0, 0, 0, 0.18);
}}

@media (min-width: 820px) {{
  .pinned-beat.has-media {{
    grid-template-columns: 1.15fr 0.85fr;
    gap: 44px;
    align-items: center;
  }}
  .pinned-beat-media {{
    max-height: 62svh;
  }}
}}

.beat-eyebrow {{
  font-size: 11px;
  letter-spacing: 0.2em;
  text-transform: uppercase;
  color: var(--accent);
  margin-bottom: 10px;
}}

.beat-heading {{
  font-size: clamp(1.5rem, 5vw, 2.5rem);
  margin-bottom: 12px;
}}

.beat-body {{
  font-size: clamp(0.95rem, 3vw, 1.08rem);
  color: var(--muted);
  max-width: 40ch;
}}

.pinned-dots {{
  position: absolute;
  bottom: 24px;
  left: 50%;
  transform: translateX(-50%);
  display: flex;
  gap: 10px;
}}

.pinned-dot {{
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: var(--border);
  transition: transform 300ms ease, background-color 300ms ease;
}}

.pinned-dot.is-active {{
  background: var(--accent);
  transform: scale(1.45);
}}

/* =========================================================
   5. VIDEO MOMENT SCENE
   ========================================================= */
.scene-video {{
  min-height: 92svh;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 72px 20px;
}}

.video-shell {{
  width: 100%;
  max-width: 920px;
  margin: 0 auto;
}}

.video-frame {{
  position: relative;
  background: #000;
  border: 1px solid var(--border);
  overflow: hidden;
  box-shadow: 0 24px 60px rgba(0, 0, 0, 0.25);
}}

.video-frame video {{
  width: 100%;
  max-height: 74svh;
  object-fit: cover;
}}

/* =========================================================
   6. ENDING SCENE
   ========================================================= */
.scene-ending {{
  min-height: 86svh;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 96px 24px max(72px, env(safe-area-inset-bottom));
  text-align: center;
}}

.ending-inner {{
  max-width: 520px;
}}

.ending-title {{
  font-size: clamp(1.8rem, 6vw, 3rem);
  margin-bottom: 16px;
}}

.ending-message {{
  font-size: 16px;
  color: var(--muted);
  margin-bottom: 32px;
}}

.ending-credits {{
  list-style: none;
  font-size: 12px;
  letter-spacing: 0.14em;
  color: var(--muted);
  margin-bottom: 36px;
  display: flex;
  flex-direction: column;
  gap: 6px;
}}

.replay-btn {{
  appearance: none;
  border: 1px solid var(--border);
  background: transparent;
  color: var(--fg);
  font-family: var(--font-body);
  font-size: 12px;
  letter-spacing: 0.16em;
  padding: 12px 26px;
  border-radius: 999px;
  cursor: pointer;
  transition: border-color 220ms ease, background-color 220ms ease;
}}

.replay-btn:hover {{
  border-color: var(--accent);
  background: color-mix(in srgb, var(--accent) 12%, transparent);
}}

/* =========================================================
   7. CURATED DESIGN PRESETS (Memoria Pastel + Toss + Editorial)
   Zero-reload switching via `body[data-theme="..."]`
   ========================================================= */

/* Preset A: Memoria Pastel Blue (Pure Minimal Typography — Zero Illustrations) */
body[data-theme="memoria_pastel"] {{
  --bg: #F4F9FF !important;
  --surface: #FFFFFF !important;
  --fg: #111827 !important;
  --muted: #6E7D91 !important;
  --accent: #4A9EFF !important;
  --border: rgba(74, 158, 255, 0.14) !important;
  --vignette: 0 !important;
  --font-display: "Pretendard", -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", sans-serif;
  background-color: #F4F9FF !important;
  color: #111827 !important;
}}

body[data-theme="memoria_pastel"] .scene-cover {{
  position: relative;
  height: 100svh;
  min-height: 100svh;
  padding: 48px 28px;
  justify-content: center;
  align-items: center;
  overflow: hidden;
  background: linear-gradient(180deg, #DCEEFF 0%, #F2F8FF 48%, #FFFFFF 100%);
}}

body[data-theme="memoria_pastel"] .cover-backdrop {{
  display: none;
}}

body[data-theme="memoria_pastel"] .scene-cover .cover-content {{
  position: relative;
  z-index: 2;
  background: transparent;
  color: #111827 !important;
  max-width: 340px;
  padding: 0;
  text-align: center;
}}

body[data-theme="memoria_pastel"] .cover-date {{
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.18em;
  color: #4A9EFF;
  opacity: 1;
  margin-bottom: 18px;
}}

body[data-theme="memoria_pastel"] .cover-title {{
  font-weight: 800;
  font-size: clamp(2.3rem, 9vw, 3.0rem);
  letter-spacing: -0.035em;
  color: #111827;
  margin-bottom: 12px;
}}

body[data-theme="memoria_pastel"] .cover-subtitle {{
  color: #6E7D91;
  font-size: 15px;
  font-weight: 400;
  letter-spacing: -0.01em;
  opacity: 1;
  margin-bottom: 40px;
}}

body[data-theme="memoria_pastel"] .enter-btn {{
  border: 1px solid rgba(74, 158, 255, 0.35);
  background: rgba(255, 255, 255, 0.85);
  color: #2B7DE9;
  font-weight: 600;
  font-size: 13px;
  letter-spacing: 0.04em;
  padding: 12px 28px;
  border-radius: 999px;
  box-shadow: 0 6px 20px rgba(74, 158, 255, 0.12);
}}

body[data-theme="memoria_pastel"] .cover-hint {{
  color: #93A1B4;
  font-size: 11px;
  opacity: 1;
  margin-top: 20px;
}}

body[data-theme="memoria_pastel"] .display-title {{
  font-weight: 700;
  letter-spacing: -0.03em;
}}

body[data-theme="memoria_pastel"] .chapter-label {{
  display: inline-block;
  background: #E8F3FF;
  color: #3687E8;
  font-weight: 700;
  font-size: 11px;
  letter-spacing: 0.04em;
  padding: 5px 12px;
  border-radius: 999px;
}}

body[data-theme="memoria_pastel"] .spotlight-frame,
body[data-theme="memoria_pastel"] .track-card-frame,
body[data-theme="memoria_pastel"] .video-frame {{
  background: #FFFFFF;
  border-radius: 26px;
  padding: 12px;
  border: 1px solid rgba(74, 158, 255, 0.14);
  box-shadow: 0 16px 38px rgba(55, 110, 180, 0.08);
}}

body[data-theme="memoria_pastel"] .spotlight-frame img,
body[data-theme="memoria_pastel"] .track-card-frame img {{
  border-radius: 18px;
}}

body[data-theme="memoria_pastel"] .audio-toggle {{
  background: rgba(255, 255, 255, 0.88);
  color: #111827;
  border: 1px solid rgba(74, 158, 255, 0.20);
  box-shadow: 0 6px 18px rgba(25, 31, 40, 0.07);
}}

body[data-theme="memoria_pastel"] .scene-ending {{
  position: relative;
  padding-bottom: 140px;
  background: linear-gradient(180deg, #F3F8FF 0%, #FFFFFF 100%);
}}

body[data-theme="memoria_pastel"] .replay-btn {{
  border: none;
  background: linear-gradient(135deg, #6EC1FF 0%, #4A9EFF 100%);
  color: #FFFFFF;
  font-weight: 700;
  letter-spacing: -0.01em;
  padding: 14px 30px;
  box-shadow: 0 10px 24px rgba(74, 158, 255, 0.28);
}}

body[data-theme="memoria_pastel"] .memoria-ending-wave {{
  display: block;
  position: absolute;
  left: 0;
  right: 0;
  bottom: 0;
  pointer-events: none;
}}

body[data-theme="memoria_pastel"] .memoria-ending-wave svg {{
  display: block;
  width: 100%;
  height: 110px;
}}

/* Preset B: Toss Clean (Simplicity · Bold Sans · 20px Soft Cards) */
body[data-theme="toss_clean"] {{
  --font-display: "Pretendard", -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo", sans-serif;
  --accent: #3182F6;
}}

body[data-theme="toss_clean"] .display-title {{
  font-weight: 700;
  letter-spacing: -0.03em;
  line-height: 1.24;
}}

body[data-theme="toss_clean"] .chapter-label {{
  font-weight: 600;
  letter-spacing: 0.04em;
  text-transform: none;
  font-size: 13px;
}}

body[data-theme="toss_clean"] .enter-btn {{
  background: #3182F6;
  border-color: transparent;
  color: #FFFFFF;
  font-weight: 600;
  letter-spacing: -0.01em;
  padding: 15px 34px;
  border-radius: 16px;
  box-shadow: 0 10px 24px rgba(49, 130, 246, 0.34);
}}

body[data-theme="toss_clean"] .spotlight-frame,
body[data-theme="toss_clean"] .track-card-frame,
body[data-theme="toss_clean"] .video-frame {{
  border-radius: 22px;
  overflow: hidden;
  padding: 0;
  border: none;
  box-shadow: 0 14px 36px rgba(25, 31, 40, 0.08);
}}

body[data-theme="toss_clean"] .spotlight-frame .plaque {{
  padding: 18px 20px 20px;
  margin-top: 0;
  border-top: none;
}}

body[data-theme="toss_clean"] .cover-scrim {{
  background: linear-gradient(
    to top,
    rgba(25, 31, 40, 0.88) 0%,
    rgba(25, 31, 40, 0.28) 54%,
    rgba(25, 31, 40, 0.08) 100%
  );
}}

body[data-theme="toss_clean"] .replay-btn {{
  border-radius: 14px;
  font-weight: 600;
  letter-spacing: -0.01em;
}}

/* Preset C: Midnight Film (Darkroom Archive · Monospace EXIF · Amber) */
body[data-theme="midnight_film"] {{
  background-color: #111110;
  color: #F3EFE8;
  --bg: #111110;
  --surface: #1A1918;
  --fg: #F3EFE8;
  --muted: #9D968B;
  --accent: #E2A86B;
  --border: rgba(243, 239, 232, 0.14);
}}

body[data-theme="midnight_film"] .chapter-label,
body[data-theme="midnight_film"] .plaque-meta,
body[data-theme="midnight_film"] .cover-date,
body[data-theme="midnight_film"] .horizontal-cue {{
  font-family: ui-monospace, "SF Mono", Menlo, monospace;
  letter-spacing: 0.14em;
}}

body[data-theme="midnight_film"] .spotlight-frame,
body[data-theme="midnight_film"] .track-card-frame {{
  background: #1B1A18;
  padding: 12px 12px 18px;
  border: 1px solid rgba(226, 168, 107, 0.24);
  border-radius: 3px;
  box-shadow: 0 24px 64px rgba(0, 0, 0, 0.55);
}}

body[data-theme="midnight_film"] .enter-btn {{
  border-radius: 4px;
  border-color: rgba(226, 168, 107, 0.65);
  background: rgba(226, 168, 107, 0.12);
  color: #F5E6D3;
  letter-spacing: 0.2em;
}}

/* Preset D: Atelier Poster (Paperless Luxury · Double Hairline · Centered) */
body[data-theme="atelier_poster"] {{
  --accent: #7B6D57;
}}

body[data-theme="atelier_poster"] .spotlight-header,
body[data-theme="atelier_poster"] .plaque {{
  text-align: center;
  margin-left: auto;
  margin-right: auto;
}}

body[data-theme="atelier_poster"] .spotlight-frame {{
  padding: clamp(18px, 4vw, 36px);
  outline: 1px solid var(--border);
  outline-offset: -8px;
  border-radius: 0;
  box-shadow: 0 22px 54px rgba(35, 31, 29, 0.08);
}}

body[data-theme="atelier_poster"] .cover-title {{
  font-size: clamp(2.4rem, 9vw, 4.6rem);
  letter-spacing: 0.02em;
}}

body[data-theme="atelier_poster"] .enter-btn {{
  border-radius: 0;
  padding: 14px 36px;
  letter-spacing: 0.22em;
  border-width: 1px;
}}
"#,
        display_font = theme.display_font,
        body_font = theme.body_font,
        transition_ms = theme.lighting_transition_ms,
    )
}
