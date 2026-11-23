/// Generate the zero-dependency Safari-compatible exhibition runtime JS:
/// - Smooth scene lighting & vignette transitions
/// - True iOS-compatible Web Audio API GainNode crossfading (with file:// HTMLAudio fallback)
/// - Continuous scroll-scrubbed PinnedStory crossfading & center-focus HorizontalTrack scaling
/// - `window.__galleryBridge` for zero-reload live DOM patching from SwiftUI WKWebView
pub fn render_runtime_js() -> &'static str {
    r#"(() => {
  'use strict';

  const root = document.documentElement;
  const progressBar = document.getElementById('progress-bar');
  const audioToggle = document.getElementById('audio-toggle');
  const audioLabel = document.getElementById('audio-label');

  // =========================================================
  // 1. iOS-Safe Web Audio GainNode Crossfade Engine
  //    (Falls back to HTMLAudio when fetch is blocked on file://)
  // =========================================================
  const audioState = {
    unlocked: false,
    muted: false,
    currentSrc: null,
    pendingCue: null,
    ctx: null,
    masterGain: null,
    activeNode: null,   // { source, gain } for Web Audio
    activeHtml: null,   // HTMLAudioElement fallback
    bufferCache: new Map(),
  };

  function ensureAudioContext() {
    if (!audioState.ctx) {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (AC) {
        audioState.ctx = new AC();
        audioState.masterGain = audioState.ctx.createGain();
        audioState.masterGain.gain.value = audioState.muted ? 0 : 1;
        audioState.masterGain.connect(audioState.ctx.destination);
      }
    }
    if (audioState.ctx && audioState.ctx.state === 'suspended') {
      audioState.ctx.resume().catch(() => {});
    }
    return audioState.ctx;
  }

  function decodeDataUriToArrayBuffer(uri) {
    const comma = uri.indexOf(',');
    if (comma < 0) return null;
    const b64 = uri.slice(comma + 1);
    const bin = atob(b64);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    return bytes.buffer;
  }

  async function loadAudioBuffer(src) {
    if (audioState.bufferCache.has(src)) return audioState.bufferCache.get(src);
    const ctx = ensureAudioContext();
    if (!ctx) return null;
    let arrBuf = null;
    if (src.startsWith('data:')) {
      arrBuf = decodeDataUriToArrayBuffer(src);
    } else if (window.location.protocol !== 'file:') {
      const res = await fetch(src);
      if (!res.ok) return null;
      arrBuf = await res.arrayBuffer();
    } else {
      return null;
    }
    if (!arrBuf) return null;
    const decoded = await ctx.decodeAudioData(arrBuf);
    audioState.bufferCache.set(src, decoded);
    return decoded;
  }

  function updateAudioButton() {
    if (!audioToggle) return;
    const hasActive = Boolean(audioState.activeNode || audioState.activeHtml);
    const isPlaying = audioState.unlocked && !audioState.muted && hasActive;
    audioToggle.setAttribute('data-playing', isPlaying ? 'true' : 'false');
    if (audioLabel) {
      audioLabel.textContent = audioState.muted
        ? 'Sound Off'
        : audioState.unlocked
          ? 'Sound On'
          : 'Sound';
    }
  }

  function playHtmlFallback(cue) {
    const prev = audioState.activeHtml;
    const next = new Audio(cue.src);
    next.loop = cue.loop !== false;
    next.preload = 'auto';
    next.volume = 0;
    audioState.activeHtml = next;

    const targetVol = typeof cue.volume === 'number' ? cue.volume : 0.5;
    const fadeMs = Math.max(150, cue.fadeMs || 1200);

    const ramp = (el, fromV, toV, done) => {
      const start = performance.now();
      function step(now) {
        const t = Math.min(1, (now - start) / fadeMs);
        try {
          el.volume = Math.max(0, Math.min(1, fromV + (toV - fromV) * t));
        } catch (_) {}
        if (t < 1) requestAnimationFrame(step);
        else if (done) done();
      }
      requestAnimationFrame(step);
    };

    next.play()
      .then(() => {
        ramp(next, 0, targetVol);
        updateAudioButton();
      })
      .catch(() => updateAudioButton());

    if (prev) {
      ramp(prev, prev.volume || targetVol, 0, () => {
        prev.pause();
        prev.src = '';
      });
    }
  }

  async function applyAudioCue(cue) {
    if (!cue || !cue.src) return;
    audioState.pendingCue = cue;

    if (!audioState.unlocked || audioState.muted) {
      updateAudioButton();
      return;
    }
    if (audioState.currentSrc === cue.src && (audioState.activeNode || audioState.activeHtml)) {
      updateAudioButton();
      return;
    }

    audioState.currentSrc = cue.src;
    const fadeSec = Math.max(0.15, (cue.fadeMs || 1200) / 1000);
    const targetVol = typeof cue.volume === 'number' ? cue.volume : 0.5;

    try {
      const buffer = await loadAudioBuffer(cue.src);
      if (buffer && audioState.ctx && audioState.masterGain) {
        const ctx = audioState.ctx;
        const now = ctx.currentTime;

        const prev = audioState.activeNode;
        if (prev) {
          prev.gain.gain.cancelScheduledValues(now);
          prev.gain.gain.setValueAtTime(prev.gain.gain.value, now);
          prev.gain.gain.linearRampToValueAtTime(0.0001, now + fadeSec);
          setTimeout(() => {
            try { prev.source.stop(); } catch (_) {}
          }, (fadeSec + 0.1) * 1000);
        }

        const source = ctx.createBufferSource();
        source.buffer = buffer;
        source.loop = cue.loop !== false;

        const gain = ctx.createGain();
        gain.gain.setValueAtTime(0.0001, now);
        gain.gain.linearRampToValueAtTime(targetVol, now + fadeSec);

        source.connect(gain);
        gain.connect(audioState.masterGain);
        source.start(now);

        audioState.activeNode = { source, gain };
        updateAudioButton();
        return;
      }
    } catch (_) {
      // Fall through to HTMLAudio fallback
    }

    playHtmlFallback(cue);
  }

  function unlockAudio() {
    if (audioState.unlocked) return;
    audioState.unlocked = true;
    audioState.muted = false;
    ensureAudioContext();
    if (audioState.pendingCue) {
      applyAudioCue(audioState.pendingCue);
    }
    updateAudioButton();
  }

  if (audioToggle) {
    audioToggle.addEventListener('click', () => {
      if (!audioState.unlocked) {
        unlockAudio();
        return;
      }
      audioState.muted = !audioState.muted;
      if (audioState.masterGain && audioState.ctx) {
        const now = audioState.ctx.currentTime;
        audioState.masterGain.gain.cancelScheduledValues(now);
        audioState.masterGain.gain.setTargetAtTime(audioState.muted ? 0 : 1, now, 0.08);
      }
      if (audioState.activeHtml) {
        if (audioState.muted) audioState.activeHtml.pause();
        else audioState.activeHtml.play().catch(() => {});
      } else if (!audioState.muted && audioState.pendingCue && !audioState.activeNode) {
        applyAudioCue(audioState.pendingCue);
      }
      updateAudioButton();
    });
  }

  document.querySelectorAll('[data-enter-exhibition]').forEach((btn) => {
    btn.addEventListener('click', () => {
      unlockAudio();
      const cover = btn.closest('.scene');
      const nextScene = cover ? cover.nextElementSibling : null;
      if (nextScene) {
        nextScene.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }
    });
  });

  document.querySelectorAll('[data-replay-exhibition]').forEach((btn) => {
    btn.addEventListener('click', () => {
      window.scrollTo({ top: 0, behavior: 'smooth' });
    });
  });

  // =========================================================
  // 2. Scene Lighting & Atmosphere Observer
  // =========================================================
  const scenes = Array.from(document.querySelectorAll('.scene'));

  function activateSceneAtmosphere(el) {
    if (!el) return;
    const ds = el.dataset;
    if (ds.bg) root.style.setProperty('--bg', ds.bg);
    if (ds.surface) root.style.setProperty('--surface', ds.surface);
    if (ds.fg) root.style.setProperty('--fg', ds.fg);
    if (ds.muted) root.style.setProperty('--muted', ds.muted);
    if (ds.accent) root.style.setProperty('--accent', ds.accent);
    if (ds.border) root.style.setProperty('--border', ds.border);
    if (ds.vignette !== undefined) root.style.setProperty('--vignette', ds.vignette);

    if (ds.audioSrc) {
      applyAudioCue({
        src: ds.audioSrc,
        volume: parseFloat(ds.audioVol || '0.5'),
        fadeMs: parseInt(ds.audioFade || '1200', 10),
        loop: ds.audioLoop !== 'false',
      });
    }
  }

  if (scenes.length > 0) {
    activateSceneAtmosphere(scenes[0]);
  }

  const sceneObserver = new IntersectionObserver(
    (entries) => {
      let best = null;
      for (const entry of entries) {
        if (entry.isIntersecting) {
          if (!best || entry.intersectionRatio > best.intersectionRatio) {
            best = entry;
          }
        }
      }
      if (best) {
        activateSceneAtmosphere(best.target);
      }
    },
    {
      rootMargin: '-35% 0px -35% 0px',
      threshold: [0, 0.15, 0.4, 0.7],
    }
  );
  scenes.forEach((s) => sceneObserver.observe(s));

  // =========================================================
  // 3. Reveal & Inline Video Observers
  // =========================================================
  const revealObserver = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-visible');
          revealObserver.unobserve(entry.target);
        }
      }
    },
    { threshold: 0.12 }
  );
  document.querySelectorAll('.reveal').forEach((el) => revealObserver.observe(el));

  const videoObserver = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        const video = entry.target;
        if (entry.isIntersecting) video.play().catch(() => {});
        else video.pause();
      }
    },
    { threshold: 0.35 }
  );
  document.querySelectorAll('video[data-autoplay="true"]').forEach((v) => videoObserver.observe(v));

  // =========================================================
  // 4. Continuous Scroll-Scrubbed Choreography
  // =========================================================
  const horizontalScenes = Array.from(document.querySelectorAll('[data-horizontal-track]')).map(
    (section) => ({
      section,
      rail: section.querySelector('.horizontal-rail'),
      cards: Array.from(section.querySelectorAll('.track-card')),
      meter: section.querySelector('.horizontal-meter-fill'),
      pace: parseFloat(section.dataset.pace || '1.0'),
      maxShift: 0,
    })
  );

  const pinnedScenes = Array.from(document.querySelectorAll('[data-pinned-story]')).map(
    (section) => ({
      section,
      beats: Array.from(section.querySelectorAll('.pinned-beat')),
      dots: Array.from(section.querySelectorAll('.pinned-dot')),
      pace: parseFloat(section.dataset.pace || '1.0'),
    })
  );

  function layoutRunways() {
    const vh = window.innerHeight || 800;
    const vw = window.innerWidth || 400;

    for (const h of horizontalScenes) {
      if (!h.rail) continue;
      const totalWidth = h.rail.scrollWidth;
      h.maxShift = Math.max(0, totalWidth - vw);
      const runway = Math.round(vh + h.maxShift * 1.15 * h.pace);
      h.section.style.height = `${Math.max(vh * 1.4, runway)}px`;
    }

    for (const p of pinnedScenes) {
      const count = Math.max(1, p.beats.length);
      const runway = Math.round(vh * (0.9 + count * 0.95 * p.pace));
      p.section.style.height = `${runway}px`;
    }
  }

  function updateChoreography() {
    const scrollY = window.scrollY || window.pageYOffset;
    const docHeight = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);

    if (progressBar) {
      progressBar.style.transform = `scaleX(${Math.max(0, Math.min(1, scrollY / docHeight))})`;
    }

    const vh = window.innerHeight || 800;
    const vw = window.innerWidth || 400;
    const centerX = vw * 0.5;

    for (const h of horizontalScenes) {
      if (!h.rail) continue;
      const rect = h.section.getBoundingClientRect();
      const scrollable = Math.max(1, h.section.offsetHeight - vh);
      const progress = Math.max(0, Math.min(1, -rect.top / scrollable));
      const shift = progress * h.maxShift;
      h.rail.style.transform = `translate3d(${-shift.toFixed(1)}px, 0, 0)`;
      if (h.meter) {
        h.meter.style.transform = `scaleX(${progress.toFixed(4)})`;
      }
      // Subtle center-focus scale for each artwork card as it passes the viewer
      for (const card of h.cards) {
        const cr = card.getBoundingClientRect();
        const cardCenter = cr.left + cr.width * 0.5;
        const dist = Math.min(1, Math.abs(cardCenter - centerX) / (vw * 0.75));
        const scale = 1.0 - dist * 0.045;
        const opacity = 1.0 - dist * 0.28;
        card.style.transform = `scale(${scale.toFixed(3)})`;
        card.style.opacity = opacity.toFixed(3);
      }
    }

    // Continuous scroll-scrubbed crossfading for PinnedStory beats
    for (const p of pinnedScenes) {
      const n = p.beats.length;
      if (n === 0) continue;
      const rect = p.section.getBoundingClientRect();
      const scrollable = Math.max(1, p.section.offsetHeight - vh);
      const progress = Math.max(0, Math.min(1, -rect.top / scrollable));
      const pos = progress * Math.max(0, n - 1);
      const nearest = Math.round(pos);

      p.beats.forEach((beat, idx) => {
        const delta = pos - idx; // 0 when centered
        const absD = Math.abs(delta);
        const opacity = Math.max(0, 1 - absD * 1.35);
        const yOffset = delta * -26;
        beat.style.opacity = opacity.toFixed(3);
        beat.style.transform = `translate3d(0, ${yOffset.toFixed(1)}px, 0)`;
        beat.style.pointerEvents = absD < 0.45 ? 'auto' : 'none';
      });

      p.dots.forEach((dot, idx) => {
        dot.classList.toggle('is-active', idx === nearest);
      });
    }
  }

  let ticking = false;
  function onScroll() {
    if (!ticking) {
      ticking = true;
      requestAnimationFrame(() => {
        updateChoreography();
        ticking = false;
      });
    }
  }

  window.addEventListener('scroll', onScroll, { passive: true });
  window.addEventListener('resize', () => {
    layoutRunways();
    updateChoreography();
  });
  window.addEventListener('load', () => {
    layoutRunways();
    updateChoreography();
  });

  layoutRunways();
  updateChoreography();

  // =========================================================
  // 5. Live Editor Bridge for SwiftUI WKWebView (Zero-Reload)
  // =========================================================
  window.__galleryBridge = {
    scrollToScene(sceneId) {
      const el = document.getElementById(sceneId);
      if (!el) return false;
      el.scrollIntoView({ behavior: 'smooth', block: 'start' });
      activateSceneAtmosphere(el);
      return true;
    },

    patchSceneAtmosphere(sceneId, palette, vignette) {
      const el = document.getElementById(sceneId);
      if (!el) return false;
      el.dataset.bg = palette.background;
      el.dataset.surface = palette.surface;
      el.dataset.fg = palette.foreground;
      el.dataset.muted = palette.muted;
      el.dataset.accent = palette.accent;
      el.dataset.border = palette.border;
      el.dataset.vignette = String(vignette);
      activateSceneAtmosphere(el);
      return true;
    },

    patchSceneText(sceneId, patch) {
      const el = document.getElementById(sceneId);
      if (!el) return false;
      const setField = (name, value) => {
        const node = el.querySelector(`[data-field="${name}"]`);
        if (node && typeof value === 'string') {
          node.textContent = value;
        }
      };
      if (patch.title !== undefined) setField('title', patch.title);
      if (patch.chapter !== undefined) setField('chapter', patch.chapter);
      if (patch.note !== undefined) setField('note', patch.note);
      if (patch.caption !== undefined) setField('caption', patch.caption);
      return true;
    },

    patchSceneItem(sceneId, itemIndex, patch) {
      const el = document.getElementById(sceneId);
      if (!el) return false;
      const card = el.querySelector(`[data-item-index="${itemIndex}"]`);
      if (!card) return false;
      if (patch.title !== undefined) {
        const t = card.querySelector('[data-item-field="title"]');
        if (t) t.textContent = patch.title;
      }
      if (patch.caption !== undefined) {
        const c = card.querySelector('[data-item-field="caption"]');
        if (c) c.textContent = patch.caption;
      }
      return true;
    },

    patchTheme(themePreset) {
      document.body.dataset.theme = themePreset;
      return true;
    },
  };
})();
"#
}
