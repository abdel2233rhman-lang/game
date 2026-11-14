import { secondsLeft } from '@/lib/gameTime';

interface CountdownRingProps {
  endsAtMs: number | null;
  nowMs: number;
  totalSeconds: number;
  label: string;
}

const RADIUS = 44;
const CIRCUMFERENCE = 2 * Math.PI * RADIUS;

export function CountdownRing({ endsAtMs, nowMs, totalSeconds, label }: CountdownRingProps) {
  const remaining = secondsLeft(endsAtMs, nowMs);
  const progress = Math.min(1, remaining / totalSeconds);
  const urgent = remaining <= 5;

  return (
    <div className="relative flex h-28 w-28 shrink-0 items-center justify-center" role="timer" aria-label={`${label}: ${remaining} ثانية`}>
      <svg viewBox="0 0 100 100" className="absolute inset-0 h-full w-full -rotate-90">
        <circle cx="50" cy="50" r={RADIUS} fill="none" stroke="rgba(255,255,255,0.08)" strokeWidth="7" />
        <circle
          cx="50"
          cy="50"
          r={RADIUS}
          fill="none"
          stroke="currentColor"
          strokeWidth="7"
          strokeLinecap="round"
          className={`transition-[stroke-dashoffset] duration-300 ease-linear ${urgent ? 'text-rose-400' : 'text-neon-400'}`}
          style={{ strokeDasharray: CIRCUMFERENCE, strokeDashoffset: CIRCUMFERENCE * (1 - progress) }}
        />
      </svg>
      <div className="flex flex-col items-center">
        <span className={`font-display text-3xl font-black tabular-nums ${urgent ? 'text-rose-200' : 'text-white'}`}>
          {remaining}
        </span>
        <span className="text-[10px] font-bold text-ink-300">{label}</span>
      </div>
    </div>
  );
}
