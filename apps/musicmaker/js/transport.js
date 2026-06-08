// Shared transport: the lookahead scheduler from Chris Wilson's
// "A Tale of Two Clocks". A setInterval-ish timer schedules notes whose
// time falls inside a short window ahead of the audio clock; each hit is
// stamped with an exact AudioContext time. A separate rAF loop drives the
// on-screen playhead, decoupled from audio scheduling.

import { resume, now } from './audio.js';

export const transport = {
  bpm: 120,
  swing: 0,            // 0..0.6, delays odd 16ths
  isPlaying: false,
  currentStep: -1,
  stepCallback: null,  // (step, time) => schedule audio for that step
  drawCallback: null   // (step) => light the UI column (or -1 to clear)
};

const STEPS = 16;
const LOOKAHEAD = 25;  // ms between scheduler passes
const AHEAD = 0.1;     // s scheduling window
const noteQueue = [];  // {step, time} pending for the visual playhead

let nextNoteTime = 0;
let current16 = 0;
let timerId = null;
let rafId = null;

function secPerStep() { return (60 / transport.bpm) / 4; } // 16th notes

function scheduleStep(step, time) {
  noteQueue.push({ step, time });
  if (transport.stepCallback) transport.stepCallback(step, time);
}

function advance() {
  nextNoteTime += secPerStep();
  current16 = (current16 + 1) % STEPS;
}

function scheduler() {
  const horizon = now() + AHEAD;
  while (nextNoteTime < horizon) {
    // Swing: push the off-beat 16ths a little later.
    let t = nextNoteTime;
    if (transport.swing > 0 && current16 % 2 === 1) t += secPerStep() * transport.swing * 0.5;
    scheduleStep(current16, t);
    advance();
  }
  timerId = setTimeout(scheduler, LOOKAHEAD);
}

function draw() {
  const t = now();
  let step = transport.currentStep;
  while (noteQueue.length && noteQueue[0].time <= t) step = noteQueue.shift().step;
  if (step !== transport.currentStep) {
    transport.currentStep = step;
    if (transport.drawCallback) transport.drawCallback(step);
  }
  rafId = requestAnimationFrame(draw);
}

export function start() {
  if (transport.isPlaying) return;
  resume();
  transport.isPlaying = true;
  current16 = 0;
  nextNoteTime = now() + 0.06; // small head start
  noteQueue.length = 0;
  scheduler();
  rafId = requestAnimationFrame(draw);
}

export function stop() {
  transport.isPlaying = false;
  clearTimeout(timerId);
  cancelAnimationFrame(rafId);
  noteQueue.length = 0;
  transport.currentStep = -1;
  if (transport.drawCallback) transport.drawCallback(-1);
}

export function setBpm(b) { transport.bpm = Math.min(200, Math.max(60, b || 120)); }
export function setSwing(s) { transport.swing = Math.min(0.6, Math.max(0, s || 0)); }
