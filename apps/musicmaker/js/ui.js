// UI wiring: builds the sequencer grid + piano, handles pointer/keyboard
// input, the waveform trimmer, and connects the transport to the drums.

import { resume, setMasterVolume } from './audio.js';
import { transport, start, stop, setBpm, setSwing } from './transport.js';
import { drums } from './drums.js';
import * as sampler from './sampler.js';

const $ = id => document.getElementById(id);
const NOTE_NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
const noteName = m => NOTE_NAMES[m % 12] + (Math.floor(m / 12) - 1);
const isBlack = m => [1, 3, 6, 8, 10].includes(m % 12);

const KB_LOW = 48, KB_HIGH = 72; // displayed piano range C3..C5

/* ─────────── first gesture unlocks audio ─────────── */
function unlock() { resume(); }
['pointerdown', 'keydown'].forEach(ev => window.addEventListener(ev, unlock, { once: true }));

/* ═══════════ DRUM GRID ═══════════ */
const stepColumns = Array.from({ length: drums.steps }, () => []);
function buildGrid() {
  const grid = $('grid');
  grid.style.setProperty('--steps', drums.steps);
  drums.tracks.forEach((name, t) => {
    const label = document.createElement('div');
    label.className = 'trk-label';
    label.textContent = name;
    grid.appendChild(label);
    for (let s = 0; s < drums.steps; s++) {
      const cell = document.createElement('button');
      cell.className = 'cell' + (s % 4 === 0 ? ' beat' : '') + (drums.isOn(t, s) ? ' on' : '');
      cell.dataset.t = t; cell.dataset.s = s;
      cell.addEventListener('pointerdown', e => {
        e.preventDefault();
        const on = drums.toggle(t, s);
        cell.classList.toggle('on', on);
        if (on) drums.audition(t);
      });
      stepColumns[s].push(cell);
      grid.appendChild(cell);
    }
  });
}
function lightStep(step) {
  stepColumns.forEach((col, s) => col.forEach(c => c.classList.toggle('playing', s === step)));
}

/* ═══════════ PIANO ═══════════ */
let baseMidi = 60; // computer-keyboard octave anchor (Ableton 'a' = this note)
function buildPiano() {
  const keys = $('keys');
  const whites = [];
  for (let m = KB_LOW; m <= KB_HIGH; m++) if (!isBlack(m)) whites.push(m);
  const wWidth = 100 / whites.length;

  // white keys first (flow), black keys positioned over them
  whites.forEach((m, i) => {
    const k = document.createElement('button');
    k.className = 'key white'; k.dataset.midi = m;
    k.style.width = wWidth + '%'; k.style.left = (i * wWidth) + '%';
    keys.appendChild(k);
  });
  for (let m = KB_LOW; m <= KB_HIGH; m++) {
    if (!isBlack(m)) continue;
    // count white keys before this midi to place the black key on the seam
    let wb = 0; for (let x = KB_LOW; x < m; x++) if (!isBlack(x)) wb++;
    const k = document.createElement('button');
    k.className = 'key black'; k.dataset.midi = m;
    k.style.width = (wWidth * 0.62) + '%';
    k.style.left = (wb * wWidth - wWidth * 0.31) + '%';
    keys.appendChild(k);
  }

  // pointer play (works for mouse + touch)
  keys.querySelectorAll('.key').forEach(k => {
    const midi = +k.dataset.midi;
    k.addEventListener('pointerdown', e => { e.preventDefault(); k.setPointerCapture(e.pointerId); press(midi, k); });
    k.addEventListener('pointerup', () => release(midi, k));
    k.addEventListener('pointercancel', () => release(midi, k));
    k.addEventListener('pointerleave', e => { if (e.buttons) release(midi, k); });
  });
}
function press(midi, el) { sampler.noteOn(midi); if (el) el.classList.add('active'); }
function release(midi, el) { sampler.noteOff(midi); if (el) el.classList.remove('active'); }
function keyEl(midi) { return $('keys').querySelector(`.key[data-midi="${midi}"]`); }

/* ═══════════ COMPUTER KEYBOARD (Ableton-style) ═══════════ */
const KMAP = { a: 0, w: 1, s: 2, e: 3, d: 4, f: 5, t: 6, g: 7, y: 8, h: 9, u: 10, j: 11, k: 12 };
const down = new Set();
function octave(delta) {
  baseMidi = Math.min(96, Math.max(24, baseMidi + delta * 12));
  $('octLabel').textContent = noteName(baseMidi);
}
window.addEventListener('keydown', e => {
  if (e.repeat || e.metaKey || e.ctrlKey || e.altKey) return;
  const tag = (e.target.tagName || '').toLowerCase();
  if (tag === 'input' || tag === 'select' || tag === 'textarea') return;
  const key = e.key.toLowerCase();
  if (key === ' ') { e.preventDefault(); toggleTransport(); return; }
  if (key === 'z') { octave(-1); return; }
  if (key === 'x') { octave(1); return; }
  if (key in KMAP && !down.has(key)) {
    down.add(key);
    const midi = baseMidi + KMAP[key];
    press(midi, keyEl(midi));
  }
});
window.addEventListener('keyup', e => {
  const key = e.key.toLowerCase();
  if (key in KMAP && down.has(key)) {
    down.delete(key);
    const midi = baseMidi + KMAP[key];
    release(midi, keyEl(midi));
  }
});

/* ═══════════ WAVEFORM + TRIM ═══════════ */
let canvas, cctx;
function sizeCanvas() {
  const wrap = $('waveWrap');
  canvas.width = wrap.clientWidth; canvas.height = 120;
  drawWave();
}
function drawWave() {
  if (!cctx) return;
  const w = canvas.width, h = canvas.height;
  cctx.clearRect(0, 0, w, h);
  const buf = sampler.sampler.buffer;
  cctx.fillStyle = '#0c1622'; cctx.fillRect(0, 0, w, h);
  if (!buf) {
    cctx.fillStyle = '#3a4d63'; cctx.font = '13px monospace'; cctx.textAlign = 'center';
    cctx.fillText('load or record a clip', w / 2, h / 2);
    $('hStart').style.display = $('hEnd').style.display = 'none';
    return;
  }
  const dur = buf.duration;
  const x0 = (sampler.sampler.trimStart / dur) * w;
  const x1 = (sampler.sampler.trimEnd / dur) * w;
  // trimmed region highlight
  cctx.fillStyle = '#0e2a3a'; cctx.fillRect(x0, 0, x1 - x0, h);
  // waveform (min/max per column)
  const data = buf.getChannelData(0), step = Math.max(1, Math.floor(data.length / w));
  const mid = h / 2;
  for (let x = 0; x < w; x++) {
    let min = 1, max = -1;
    for (let i = 0; i < step; i++) { const v = data[x * step + i] || 0; if (v < min) min = v; if (v > max) max = v; }
    const inTrim = x >= x0 && x <= x1;
    cctx.fillStyle = inTrim ? '#38bdf8' : '#2a4459';
    cctx.fillRect(x, mid + min * mid * 0.92, 1, Math.max(1, (max - min) * mid * 0.92));
  }
  const hs = $('hStart'), he = $('hEnd');
  hs.style.display = he.style.display = 'block';
  hs.style.left = x0 + 'px'; he.style.left = x1 + 'px';
}
function dragHandle(handle, which) {
  handle.addEventListener('pointerdown', e => {
    e.preventDefault(); handle.setPointerCapture(e.pointerId);
    const rect = canvas.getBoundingClientRect();
    const move = ev => {
      const buf = sampler.sampler.buffer; if (!buf) return;
      let frac = (ev.clientX - rect.left) / rect.width;
      frac = Math.min(1, Math.max(0, frac));
      let t = frac * buf.duration;
      if (which === 'start') sampler.sampler.trimStart = Math.min(t, sampler.sampler.trimEnd - 0.02);
      else sampler.sampler.trimEnd = Math.max(t, sampler.sampler.trimStart + 0.02);
      drawWave();
    };
    const up = () => { window.removeEventListener('pointermove', move); window.removeEventListener('pointerup', up); };
    window.addEventListener('pointermove', move); window.addEventListener('pointerup', up);
  });
}

/* ═══════════ TRANSPORT + CONTROLS ═══════════ */
function toggleTransport() {
  if (transport.isPlaying) { stop(); $('playBtn').classList.remove('on'); $('playBtn').textContent = '▶ Play'; }
  else { start(); $('playBtn').classList.add('on'); $('playBtn').textContent = '■ Stop'; }
}

function buildRootSelect() {
  const sel = $('rootSel');
  for (let m = KB_LOW; m <= KB_HIGH; m++) {
    const o = document.createElement('option'); o.value = m; o.textContent = noteName(m);
    if (m === 60) o.selected = true;
    sel.appendChild(o);
  }
  sel.addEventListener('change', () => { sampler.sampler.rootNote = +sel.value; });
}

/* ─── load / record ─── */
async function loadFile(file) {
  try {
    $('status').textContent = 'decoding…';
    const arr = await file.arrayBuffer();
    await sampler.decodeArrayBuffer(arr);
    drawWave();
    $('status').textContent = file.name;
  } catch (e) { $('status').textContent = 'could not decode that file'; }
}

let recorder = null, chunks = [];
async function toggleRecord() {
  const btn = $('recBtn');
  if (recorder && recorder.state === 'recording') { recorder.stop(); return; }
  if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
    $('status').textContent = 'recording not supported here'; return;
  }
  try {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    recorder = new MediaRecorder(stream); chunks = [];
    recorder.ondataavailable = e => { if (e.data.size) chunks.push(e.data); };
    recorder.onstop = async () => {
      stream.getTracks().forEach(t => t.stop());
      btn.classList.remove('rec'); btn.textContent = '● Rec';
      try {
        const blob = new Blob(chunks, { type: chunks[0] ? chunks[0].type : 'audio/webm' });
        await sampler.decodeArrayBuffer(await blob.arrayBuffer());
        drawWave(); $('status').textContent = 'recorded clip';
      } catch (e) { $('status').textContent = 'could not decode recording'; }
    };
    recorder.start();
    btn.classList.add('rec'); btn.textContent = '■ Stop';
    $('status').textContent = 'recording…';
  } catch (e) {
    $('status').textContent = 'mic blocked — allow access to record';
  }
}

/* ═══════════ INIT ═══════════ */
function init() {
  buildGrid();
  buildPiano();
  buildRootSelect();

  canvas = $('wave'); cctx = canvas.getContext('2d');
  sizeCanvas();
  window.addEventListener('resize', sizeCanvas);
  dragHandle($('hStart'), 'start');
  dragHandle($('hEnd'), 'end');

  // transport hooks
  transport.stepCallback = (step, time) => drums.trigger(step, time);
  transport.drawCallback = lightStep;

  // transport controls
  $('playBtn').addEventListener('click', toggleTransport);
  $('bpm').addEventListener('input', e => { setBpm(+e.target.value); $('bpmVal').textContent = transport.bpm; });
  $('swing').addEventListener('input', e => setSwing(+e.target.value));
  $('masterVol').addEventListener('input', e => setMasterVolume(+e.target.value));
  $('drumVol').addEventListener('input', e => drums.setVolume(+e.target.value));

  // sampler controls
  $('fileInput').addEventListener('change', e => { if (e.target.files[0]) loadFile(e.target.files[0]); });
  $('recBtn').addEventListener('click', toggleRecord);
  $('previewBtn').addEventListener('click', () => { resume(); sampler.preview(); });
  $('sampVol').addEventListener('input', e => sampler.setVolume(+e.target.value));
  $('octDown').addEventListener('click', () => octave(-1));
  $('octUp').addEventListener('click', () => octave(1));
  $('octLabel').textContent = noteName(baseMidi);

  $('modeBtn').addEventListener('click', () => {
    sampler.sampler.mode = sampler.sampler.mode === 'oneshot' ? 'gate' : 'oneshot';
    $('modeBtn').textContent = 'Mode: ' + (sampler.sampler.mode === 'oneshot' ? 'One-shot' : 'Gate');
  });
  $('revBtn').addEventListener('click', () => {
    sampler.sampler.reverse = !sampler.sampler.reverse;
    $('revBtn').classList.toggle('on', sampler.sampler.reverse);
  });

  // register the app's service worker (relative path for the Pages subpath)
  if ('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js').catch(() => {});
}

init();
