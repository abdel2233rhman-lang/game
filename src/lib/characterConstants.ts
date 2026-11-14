import { Eye, EyeOff, Focus, Zap, type LucideIcon } from 'lucide-react';
import type { CharacterCategory, CharacterMode, QuestionAnswer, QuestionKey } from '@/lib/characterApi';

export const CHARACTER_CATEGORIES: { key: CharacterCategory; label: string }[] = [
  { key: 'football', label: 'لاعبو كرة القدم' },
  { key: 'arab_artists', label: 'الفنانون والمطربون العرب' },
  { key: 'world_celebrities', label: 'المشاهير العالميون' },
  { key: 'actors', label: 'الممثلون' },
  { key: 'cartoon', label: 'الشخصيات الكرتونية' },
  { key: 'historical', label: 'الشخصيات التاريخية' },
  { key: 'games_movies', label: 'شخصيات الألعاب والأفلام' },
];

export const CATEGORY_LABEL: Record<CharacterCategory, string> = Object.fromEntries(
  CHARACTER_CATEGORIES.map((c) => [c.key, c.label]),
) as Record<CharacterCategory, string>;

export interface ModeInfo {
  key: CharacterMode;
  title: string;
  text: string;
  Icon: LucideIcon;
  defaults: { roundSeconds: number; questionsPerPlayer: number };
}

export const CHARACTER_MODES: ModeInfo[] = [
  {
    key: 'classic',
    title: 'Classic',
    text: 'تظهر صورة الشخصية من البداية، مع تلميحات تتكشف تدريجيًا وأسئلة محدودة.',
    Icon: Eye,
    defaults: { roundSeconds: 45, questionsPerPlayer: 3 },
  },
  {
    key: 'mystery',
    title: 'Mystery',
    text: 'لا صورة نهائيًا. اكتشف الشخصية من التلميحات والأسئلة فقط.',
    Icon: EyeOff,
    defaults: { roundSeconds: 50, questionsPerPlayer: 3 },
  },
  {
    key: 'progressive',
    title: 'Progressive Hints',
    text: 'الصورة ضبابية جدًا وتزداد وضوحًا مع كل تلميح جديد.',
    Icon: Focus,
    defaults: { roundSeconds: 50, questionsPerPlayer: 2 },
  },
  {
    key: 'fast',
    title: 'Fast Guess',
    text: 'أسرع لاعب يحصل على +50 نقطة، وتنتهي الجولة بعد 5 ثوانٍ من أول إجابة صحيحة.',
    Icon: Zap,
    defaults: { roundSeconds: 30, questionsPerPlayer: 1 },
  },
];

export const MODE_LABEL: Record<CharacterMode, string> = {
  classic: 'Classic',
  mystery: 'Mystery',
  progressive: 'Progressive Hints',
  fast: 'Fast Guess',
};

export const ROUND_OPTIONS = [3, 5, 7, 10] as const;
export const SECONDS_OPTIONS = [20, 30, 45, 60, 90] as const;
export const QUESTION_OPTIONS = [0, 1, 2, 3, 4, 5] as const;

export const QUESTIONS: { key: QuestionKey; label: string }[] = [
  { key: 'is_real', label: 'هل الشخصية حقيقية (وليست خيالية)؟' },
  { key: 'is_male', label: 'هل الشخصية رجل / ذكر؟' },
  { key: 'is_alive', label: 'هل الشخصية على قيد الحياة؟' },
  { key: 'is_egyptian', label: 'هل الشخصية مصرية؟' },
  { key: 'is_arab', label: 'هل الشخصية عربية؟' },
];

export const QUESTION_LABEL: Record<QuestionKey, string> = Object.fromEntries(
  QUESTIONS.map((q) => [q.key, q.label]),
) as Record<QuestionKey, string>;

export const ANSWER_LABEL: Record<QuestionAnswer, string> = {
  yes: 'نعم',
  no: 'لا',
  na: 'لا أستطيع الإجابة',
};

/** Display only: the server decides the real points. */
export const HINT_POINTS = [100, 80, 60, 40, 30, 20] as const;
