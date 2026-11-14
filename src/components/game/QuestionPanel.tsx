import { useState } from 'react';
import { Check, Loader2 } from 'lucide-react';
import { CountdownRing } from '@/components/game/CountdownRing';
import { submitAnswer, type GameState } from '@/lib/gameApi';
import { CATEGORY_LABELS, DIFFICULTY_LABELS, DIFFICULTY_STYLES } from '@/lib/gameConstants';
import { getErrorMessage } from '@/lib/roomApi';
import { secondsLeft } from '@/lib/gameTime';

interface QuestionPanelProps {
  state: GameState;
  nowMs: number;
  token: string;
  onChanged: () => Promise<void>;
}

const OPTION_LETTERS = ['أ', 'ب', 'ج', 'د', 'هـ', 'و'];

const KIND_LABELS: Record<string, string> = {
  multiple_choice: 'اختيار من متعدد',
  true_false: 'صح أو خطأ',
  riddle: 'لغز',
  speed: 'تحدي السرعة',
  image: 'تحدي بصري',
};

export function QuestionPanel({ state, nowMs, token, onChanged }: QuestionPanelProps) {
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const { game, question, players, me } = state;
  if (!game || !question) return null;

  const options = question.options ?? [];
  const totalSeconds = question.time_limit ?? game.question_seconds;
  const remaining = secondsLeft(game.phase_ends_at_ms, nowMs);
  const closed = remaining <= 0;
  const hasBet = me.bet !== null && me.bet > 0;
  const canAnswer = hasBet && me.choice === null && !closed && !submitting;
  const answeredCount = players.filter((player) => player.answered).length;
  const bettorCount = players.filter((player) => player.wagered).length;

  async function answer(choice: number) {
    setSubmitting(true);
    setError(null);
    try {
      await submitAnswer(token, choice);
    } catch (err) {
      setError(getErrorMessage(err));
    } finally {
      setSubmitting(false);
      void onChanged();
    }
  }

  return (
    <section className="glass flex flex-col gap-6 p-5 sm:p-8">
      <div className="flex flex-wrap items-start justify-between gap-6">
        <div className="flex min-w-0 flex-1 flex-col gap-3">
          <div className="flex flex-wrap gap-2">
            <span className="rounded-full border border-white/15 bg-white/5 px-3 py-1 text-xs font-bold text-ink-100">
              {CATEGORY_LABELS[question.category] ?? question.category}
            </span>
            <span className={`rounded-full border px-3 py-1 text-xs font-bold ${DIFFICULTY_STYLES[question.difficulty]}`}>
              {DIFFICULTY_LABELS[question.difficulty]}
            </span>
            <span className="rounded-full border border-white/15 px-3 py-1 text-xs font-bold text-ink-300">
              {KIND_LABELS[question.kind] ?? question.kind}
            </span>
          </div>
          <h2 className="font-display text-xl font-black leading-snug text-white sm:text-2xl">
            {question.prompt ?? 'السؤال غير متاح'}
          </h2>
        </div>
        <CountdownRing endsAtMs={game.phase_ends_at_ms} nowMs={nowMs} totalSeconds={totalSeconds} label="ثانية" />
      </div>

      {question.image_url && (
        <img
          src={question.image_url}
          alt="صورة السؤال"
          className="max-h-80 w-full rounded-2xl border border-white/10 object-cover"
        />
      )}

      {!hasBet && (
        <p className="rounded-xl border border-white/10 bg-white/[0.03] px-4 py-3 text-center text-sm text-ink-300">
          لم تراهن في هذه الجولة، يمكنك متابعة الإجابات بانتظار النتيجة.
        </p>
      )}

      {options.length === 0 ? (
        <p role="alert" className="text-center text-sm text-amber-200">لا توجد خيارات لهذا السؤال.</p>
      ) : (
        <div className="grid gap-3 sm:grid-cols-2">
          {options.map((option, index) => {
            const chosen = me.choice === index;
            return (
              <button
                key={`${index}-${option}`}
                type="button"
                disabled={!canAnswer}
                onClick={() => answer(index)}
                className={`flex items-center gap-3 rounded-2xl border px-4 py-4 text-start font-bold transition duration-200 disabled:cursor-not-allowed ${
                  chosen
                    ? 'border-neon-400 bg-neon-500/20 text-white shadow-neon'
                    : 'border-white/10 bg-white/[0.04] text-ink-100 enabled:hover:-translate-y-0.5 enabled:hover:border-neon-400/60 enabled:hover:bg-white/[0.08] disabled:opacity-70'
                }`}
              >
                <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-white/10 font-display text-sm font-black text-neon-200">
                  {OPTION_LETTERS[index] ?? index + 1}
                </span>
                <span className="min-w-0 flex-1">{option}</span>
                {chosen && <Check className="h-5 w-5 shrink-0 text-neon-200" />}
              </button>
            );
          })}
        </div>
      )}

      <div className="flex flex-wrap items-center justify-between gap-3 text-sm text-ink-300">
        <span>
          أجاب {answeredCount} من {bettorCount} راهنوا
        </span>
        {me.choice !== null ? (
          <span className="inline-flex items-center gap-2 text-neon-200">
            <Loader2 className="h-4 w-4 animate-spin" />
            تم تسجيل إجابتك، بانتظار النتائج
          </span>
        ) : closed ? (
          <span className="text-amber-200">انتهى الوقت</span>
        ) : null}
      </div>

      {error && (
        <p role="alert" className="rounded-xl border border-red-400/40 bg-red-500/10 px-4 py-3 text-sm text-red-200">
          {error}
        </p>
      )}
    </section>
  );
}
