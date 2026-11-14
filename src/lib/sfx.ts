// Tiny synthesized sound effects (Web Audio). No audio files, so nothing to license.
const MUTE_KEY = 'risk-it:muted';

let ctx: AudioContext | null = null;

export function isMuted(): boolean {
  try {
    return localStorage.getItem(MUTE_KEY) === '1';
  } catch {
    return false;
  }
}

export function setMuted(value: boolean): void {
  try {
    localStorage.setItem(MUTE_KEY, value ? '1' : '0');
  } catch {
    /* storage unavailable: ignore */
  }
}

function getContext(): AudioContext | null {
  if (typeof window === 'undefined') return null;
  const Ctor = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
  if (!Ctor) return null;
  if (!ctx) ctx = new Ctor();
  if (ctx.state === 'suspended') void ctx.resume();
  return ctx;
}

function tone(freq: number, start: number, duration: number, type: OscillatorType, volume: number): void {
  const audio = getContext();
  if (!audio) return;
  const osc = audio.createOscillator();
  const gain = audio.createGain();
  const t0 = audio.currentTime + start;
  osc.type = type;
  osc.frequency.setValueAtTime(freq, t0);
  gain.gain.setValueAtTime(0.0001, t0);
  gain.gain.exponentialRampToValueAtTime(volume, t0 + 0.02);
  gain.gain.exponentialRampToValueAtTime(0.0001, t0 + duration);
  osc.connect(gain).connect(audio.destination);
  osc.start(t0);
  osc.stop(t0 + duration + 0.05);
}

export type Sfx = 'correct' | 'wrong' | 'tick' | 'go' | 'reveal' | 'win' | 'hint';

export function playSfx(kind: Sfx): void {
  if (isMuted()) return;
  switch (kind) {
    case 'correct':
      tone(523, 0, 0.14, 'triangle', 0.18);
      tone(659, 0.1, 0.14, 'triangle', 0.18);
      tone(784, 0.2, 0.28, 'triangle', 0.2);
      break;
    case 'wrong':
      tone(220, 0, 0.18, 'sawtooth', 0.12);
      tone(165, 0.14, 0.28, 'sawtooth', 0.12);
      break;
    case 'tick':
      tone(880, 0, 0.07, 'square', 0.06);
      break;
    case 'go':
      tone(988, 0, 0.3, 'triangle', 0.18);
      break;
    case 'hint':
      tone(740, 0, 0.1, 'sine', 0.12);
      tone(988, 0.08, 0.14, 'sine', 0.12);
      break;
    case 'reveal':
      tone(392, 0, 0.16, 'triangle', 0.14);
      tone(494, 0.14, 0.2, 'triangle', 0.14);
      break;
    case 'win':
      [523, 659, 784, 1047].forEach((f, i) => tone(f, i * 0.13, 0.3, 'triangle', 0.18));
      break;
  }
}
