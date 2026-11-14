import type { Difficulty } from '@/lib/gameApi';

export const BET_OPTIONS = [100, 200, 300, 500, 700, 1000] as const;

export const QUESTION_SECONDS_OPTIONS = [10, 15, 20, 30, 45, 60] as const;

export const CATEGORY_LABELS: Record<string, string> = {
  general: 'ثقافة عامة',
  football: 'كرة القدم',
  movies: 'أفلام ومسلسلات',
  science: 'علوم',
  geography: 'جغرافيا',
  history: 'تاريخ',
  math: 'رياضيات',
  puzzles: 'ألغاز منطقية',
  visual: 'تحديات بصرية',
  speed: 'تحديات السرعة',
  funny: 'تحديات مضحكة',
  crazy: 'تحديات جنونية',
};

export const DIFFICULTY_LABELS: Record<Difficulty, string> = {
  easy: 'سهل',
  medium: 'متوسط',
  hard: 'صعب',
  insane: 'جنوني',
};

export const DIFFICULTY_PAYOUT: Record<Difficulty, string> = {
  easy: '×1',
  medium: '×1.5',
  hard: '×2',
  insane: '×3',
};

export const BETTING_SECONDS = 15;

export const REVEAL_SECONDS = 10;

export const DIFFICULTY_STYLES: Record<Difficulty, string> = {
  easy: 'border-emerald-400/50 bg-emerald-500/10 text-emerald-200',
  medium: 'border-sky-400/50 bg-sky-500/10 text-sky-200',
  hard: 'border-amber-400/50 bg-amber-500/10 text-amber-200',
  insane: 'border-rose-400/60 bg-rose-500/10 text-rose-200',
};
