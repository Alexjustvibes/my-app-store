// Shared audio core: one AudioContext + master chain for the whole app.
// Master chain: sources -> masterGain -> DynamicsCompressor (limiter) -> destination
// so stacking many voices never hard-clips.

let ctx = null;
let masterGain = null;
let limiter = null;

export function getCtx() {
  if (!ctx) {
    ctx = new (window.AudioContext || window.webkitAudioContext)();
    masterGain = ctx.createGain();
    masterGain.gain.value = 0.9;

    // Brick-wall-ish limiter so overlapping sampler voices + drums don't clip.
    limiter = ctx.createDynamicsCompressor();
    limiter.threshold.value = -3;
    limiter.knee.value = 0;
    limiter.ratio.value = 20;
    limiter.attack.value = 0.003;
    limiter.release.value = 0.25;

    masterGain.connect(limiter);
    limiter.connect(ctx.destination);
  }
  return ctx;
}

// Instruments connect their output here.
export function master() { getCtx(); return masterGain; }

// Must be called from a user gesture (autoplay policy).
export function resume() {
  const c = getCtx();
  if (c.state === 'suspended') c.resume();
  return c;
}

export function now() { return getCtx().currentTime; }

export function setMasterVolume(v) { master().gain.value = v; }
