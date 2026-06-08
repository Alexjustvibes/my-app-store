// Drum machine: 4 synthesized voices (no sample files), a 16-step pattern,
// and a step trigger the transport calls with an exact audio-clock time.

import { getCtx, master, now } from './audio.js';

const TRACKS = ['Kick', 'Snare', 'Hat', 'Clap'];
const STEPS = 16;

let busGain = null;
function bus() {
  if (!busGain) { busGain = getCtx().createGain(); busGain.gain.value = 0.9; busGain.connect(master()); }
  return busGain;
}

// pattern[track][step] = boolean
const pattern = TRACKS.map(() => new Array(STEPS).fill(false));

// A starter groove so hitting Play immediately makes sound.
(function seed() {
  [0, 4, 8, 12].forEach(s => pattern[0][s] = true);  // four-on-the-floor kick
  [4, 12].forEach(s => pattern[1][s] = true);          // backbeat snare
  for (let s = 0; s < STEPS; s += 2) pattern[2][s] = true; // 8th-note hats
})();

// Short white-noise buffer, rebuilt per hit (cheap, keeps voices independent).
function noiseBuffer(dur) {
  const ctx = getCtx();
  const len = Math.max(1, Math.floor(ctx.sampleRate * dur));
  const buf = ctx.createBuffer(1, len, ctx.sampleRate);
  const d = buf.getChannelData(0);
  for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
  return buf;
}

function kick(time) {
  const ctx = getCtx();
  const o = ctx.createOscillator(), g = ctx.createGain();
  o.type = 'sine';
  o.frequency.setValueAtTime(150, time);                   // pitch glide 150 -> 50
  o.frequency.exponentialRampToValueAtTime(50, time + 0.1);
  g.gain.setValueAtTime(1, time);
  g.gain.exponentialRampToValueAtTime(0.001, time + 0.4);  // fast amp decay
  o.connect(g).connect(bus());
  o.start(time); o.stop(time + 0.42);
}

function snare(time) {
  const ctx = getCtx();
  // noise crack through a high-pass
  const n = ctx.createBufferSource(); n.buffer = noiseBuffer(0.2);
  const hp = ctx.createBiquadFilter(); hp.type = 'highpass'; hp.frequency.value = 1500;
  const ng = ctx.createGain();
  ng.gain.setValueAtTime(0.8, time); ng.gain.exponentialRampToValueAtTime(0.001, time + 0.2);
  n.connect(hp).connect(ng).connect(bus()); n.start(time); n.stop(time + 0.2);
  // short triangle body for tone
  const o = ctx.createOscillator(); o.type = 'triangle'; o.frequency.setValueAtTime(180, time);
  const og = ctx.createGain(); og.gain.setValueAtTime(0.5, time); og.gain.exponentialRampToValueAtTime(0.001, time + 0.12);
  o.connect(og).connect(bus()); o.start(time); o.stop(time + 0.13);
}

function hat(time) {
  const ctx = getCtx();
  const n = ctx.createBufferSource(); n.buffer = noiseBuffer(0.06);
  const hp = ctx.createBiquadFilter(); hp.type = 'highpass'; hp.frequency.value = 7000;
  const g = ctx.createGain();
  g.gain.setValueAtTime(0.5, time); g.gain.exponentialRampToValueAtTime(0.001, time + 0.05); // very short
  n.connect(hp).connect(g).connect(bus()); n.start(time); n.stop(time + 0.06);
}

function clap(time) {
  const ctx = getCtx();
  const bp = ctx.createBiquadFilter(); bp.type = 'bandpass'; bp.frequency.value = 1200; bp.Q.value = 1.2;
  const g = ctx.createGain(); bp.connect(g); g.connect(bus());
  // three quick noise bursts a few ms apart
  [0, 0.012, 0.024].forEach(off => {
    const n = ctx.createBufferSource(); n.buffer = noiseBuffer(0.05);
    n.connect(bp); n.start(time + off); n.stop(time + off + 0.05);
  });
  g.gain.setValueAtTime(0.7, time);
  g.gain.exponentialRampToValueAtTime(0.001, time + 0.12);
}

const VOICES = [kick, snare, hat, clap];

export const drums = {
  tracks: TRACKS,
  steps: STEPS,
  pattern,
  toggle(t, s) { pattern[t][s] = !pattern[t][s]; return pattern[t][s]; },
  isOn(t, s) { return pattern[t][s]; },
  // Called by the transport for each 16th with an exact audio-clock time.
  trigger(step, time) {
    for (let t = 0; t < VOICES.length; t++) if (pattern[t][step]) VOICES[t](time);
  },
  audition(t) { VOICES[t](now() + 0.001); }, // preview a voice when toggled
  setVolume(v) { bus().gain.value = v; }
};
