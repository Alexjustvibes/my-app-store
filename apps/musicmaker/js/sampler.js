// Varispeed sampler: play a trimmed clip across the keyboard. Each key sets
// playbackRate = 2^((midi - root)/12), so pitch and speed move together
// (SP-404/MPC style). Polyphonic, with short anti-click envelopes.

import { getCtx, master, now } from './audio.js';

export const sampler = {
  buffer: null,
  reversedBuffer: null,
  rootNote: 60,        // middle C
  trimStart: 0,        // seconds, in the buffer's own timeline
  trimEnd: 0,
  mode: 'oneshot',     // 'oneshot' | 'gate'
  reverse: false
};

const ATT = 0.005, REL = 0.03;        // ~5ms attack, ~30ms release
const gateVoices = new Map();          // midi -> {src, g} for held notes

let outGain = null;
function out() {
  if (!outGain) { outGain = getCtx().createGain(); outGain.gain.value = 0.9; outGain.connect(master()); }
  return outGain;
}
export function setVolume(v) { out().gain.value = v; }

export function setBuffer(buf) {
  sampler.buffer = buf;
  sampler.reversedBuffer = null;
  sampler.trimStart = 0;
  sampler.trimEnd = buf.duration;
}

export function decodeArrayBuffer(arrBuf) {
  // Promise wrapper (Safari historically wanted the callback form).
  return new Promise((res, rej) => {
    getCtx().decodeAudioData(arrBuf, b => { setBuffer(b); res(b); }, e => rej(e || new Error('decode failed')));
  });
}

// Build (and cache) a reversed copy of the current buffer.
function reversed() {
  if (sampler.reversedBuffer) return sampler.reversedBuffer;
  const ctx = getCtx(), b = sampler.buffer;
  const rb = ctx.createBuffer(b.numberOfChannels, b.length, b.sampleRate);
  for (let ch = 0; ch < b.numberOfChannels; ch++) {
    const src = b.getChannelData(ch), dst = rb.getChannelData(ch);
    for (let i = 0, n = b.length; i < n; i++) dst[i] = src[n - 1 - i];
  }
  sampler.reversedBuffer = rb;
  return rb;
}

function startVoice(midi, held) {
  if (!sampler.buffer) return null;
  const ctx = getCtx();
  const total = sampler.buffer.duration;
  const src = ctx.createBufferSource();
  src.buffer = sampler.reverse ? reversed() : sampler.buffer;

  // Trim region in buffer seconds. For the reversed buffer, mirror the offset.
  const region = Math.max(0.02, sampler.trimEnd - sampler.trimStart);
  const offset = sampler.reverse ? (total - sampler.trimEnd) : sampler.trimStart;

  const rate = Math.pow(2, (midi - sampler.rootNote) / 12);
  src.playbackRate.value = rate;

  const g = ctx.createGain();
  const t = now();
  g.gain.setValueAtTime(0.0001, t);
  g.gain.exponentialRampToValueAtTime(1, t + ATT);   // soft attack, no click
  src.connect(g).connect(out());

  const realDur = region / rate;                      // wall-clock length after pitch
  const stopAt = t + realDur;
  const relStart = Math.max(t + ATT, stopAt - REL);

  if (held && sampler.mode === 'gate') {
    src.start(t, offset);                             // play, release on key-up
  } else {
    src.start(t, offset, region);                     // one-shot: whole region
  }
  // Safety release so even held notes never run past the trim with a click.
  g.gain.setValueAtTime(1, relStart);
  g.gain.exponentialRampToValueAtTime(0.0001, stopAt);
  src.stop(stopAt + 0.02);

  const voice = { src, g };
  src.onended = () => { if (gateVoices.get(midi) === voice) gateVoices.delete(midi); };
  return voice;
}

export function noteOn(midi) {
  if (!sampler.buffer) return;
  if (sampler.mode === 'gate') {
    if (gateVoices.has(midi)) release(midi);
    const v = startVoice(midi, true);
    if (v) gateVoices.set(midi, v);
  } else {
    startVoice(midi, false); // overlapping one-shots = polyphony
  }
}

function release(midi) {
  const v = gateVoices.get(midi);
  if (!v) return;
  gateVoices.delete(midi);
  const t = now();
  try {
    v.g.gain.cancelScheduledValues(t);
    v.g.gain.setValueAtTime(v.g.gain.value, t);
    v.g.gain.exponentialRampToValueAtTime(0.0001, t + REL);
    v.src.stop(t + REL + 0.02);
  } catch (e) { /* already stopped */ }
}

export function noteOff(midi) {
  if (sampler.mode === 'gate') release(midi);
}

export function preview() {
  if (!sampler.buffer) return;
  startVoice(sampler.rootNote, false); // trimmed region at root pitch
}
