export function secondsLeft(endsAtMs: number | null, nowMs: number): number {
  if (endsAtMs === null) return 0;
  return Math.max(0, Math.ceil((endsAtMs - nowMs) / 1000));
}
