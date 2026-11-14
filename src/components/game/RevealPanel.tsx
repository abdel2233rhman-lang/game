import { Check, Clock, Minus, X } from 'lucide-react';
import { AnimatedNumber } from '@/components/game/AnimatedNumber';
import { CountdownRing } from '@/components/game/CountdownRing';
import type { GameState, RoundResult } from '@/lib/gameApi';
import { REVEAL_SECONDS } from '@/lib/gameConstants';

interface RevealPanelProps {
  state: GameState;
  nowMs: number;
}

const OPTION_LETTERS = ['أ', 'ب', 'ج', 'د', 'هـ', 'و'];

type Outcome = 'correct' | 'wrong' | 'timeout' | 'skipped';

function outcomeOf(result: RoundResult | undefined): Outcome {
  if (!result || result.bet === 0) return 'skipped';
  if (result.choice === null) return 'timeout';
  return result.is_correct ? 'correct' : 'wrong';
}

const OUTCOME_TEXT: Record<Outcome, string> = {
  correct: 'إجابة صحيحة',
  wrong: 'إجابة خاطئة',
  timeout: 'لم يُجب في الوقت',
  skipped: 'لم يراهن',
};

const OUTCOME_CLASS: Record<Outcome, string> = {
  correct: 'text-emerald-200',
  wrong: 'text-rose-200',
  timeout: 'text-amber-200',
  skipped: 'text-ink-400',
};

function OutcomeIcon({ outcome }: { outcome: Outcome }) {
  if (outcome === 'correct') return <Check className="h-4 w-4" />;
  if (outcome === 'wrong') return <X className="h-4 w-4" />;
  if (outcome === 'timeout') return <Clock className="h-4 w-4" />;
  return <Minus className="h-4 w-4" />;
}

function formatDelta(delta: number): string {
  return `${delta > 0 ? '+' : ''}${delta.toLocaleString('en-US')}`;
}

export function RevealPanel({ state, nowMs }: RevealPanelProps) {
  const { game, question, reveal, players, me } = state;
  if (!game || !question || !reveal) return null;

  const nameOf = new Map(players.map((player) => [player.player_id, player.name]));
  const myResult = reveal.results.find((result) => result.player_id === me.player_id);
  const myOutcome = outcomeOf(myResult);
  const bettors = reveal.results.filter((result) => result.bet > 0);
  const options = question.options ?? [];

  return (
    <section className="glass flex flex-col gap-6 p-5 sm:p-8">
      <div className="flex flex-wrap items-center justify-between gap-6">
        <div className="flex min-w-0 flex-1 flex-col gap-2">
          <p className="text-sm font-bold text-ink-300">النتيجة</p>
          <h2 className="font-display text-xl font-black leading-snug text-white sm:text-2xl">{question.prompt}</h2>
        </div>
        <CountdownRing endsAtMs={game.phase_ends_at_ms} nowMs={nowMs} totalSeconds={REVEAL_SECONDS} label="الجولة التالية" />
      </div>

      <div className="grid gap-3 sm:grid-cols-2">
        {options.map((option, index) => {
          const isCorrect = index === reveal.correct_index;
          const isMyWrong = myResult?.choice === index && !isCorrect;
          return (
            <div
              key={`${index}-${option}`}
              className={`flex items-center gap-3 rounded-2xl border px-4 py-4 font-bold ${
                isCorrect
                  ? 'border-emerald-400/60 bg-emerald-500/15 text-emerald-100'
                  : isMyWrong
                    ? 'border-rose-400/60 bg-rose-500/10 text-rose-100'
                    : 'border-white/10 bg-white/[0.02] text-ink-400'
              }`}
            >
              <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-white/10 font-display text-sm font-black">
                {OPTION_LETTERS[index] ?? index + 1}
              </span>
              <span className="min-w-0 flex-1">{option}</span>
              {isCorrect && <Check className="h-5 w-5 shrink-0" />}
            </div>
          );
        })}
      </div>

      <div className="rounded-2xl border border-white/10 bg-white/[0.03] p-5 text-center">
        <p className={`text-sm font-bold ${OUTCOME_CLASS[myOutcome]}`}>{OUTCOME_TEXT[myOutcome]}</p>
        <p className="mt-2 font-display text-4xl font-black text-gold-300">
          {myResult ? (
            <>
              {myResult.delta > 0 && '+'}
              <AnimatedNumber value={myResult.delta} />
            </>
          ) : (
            <AnimatedNumber value={0} />
          )}
        </p>
        <p className="mt-1 text-xs text-ink-400">رصيدك الآن: {(players.find((player) => player.is_me)?.balance ?? 0).toLocaleString('en-US')}</p>
      </div>

      <div>
        <span className="label">رهانات الجولة</span>
        {bettors.length === 0 ? (
          <p className="text-sm text-ink-400">لم يراهن أحد في هذه الجولة.</p>
        ) : (
          <ul className="flex flex-col gap-2">
            {bettors.map((result) => {
              const outcome = outcomeOf(result);
              return (
                <li
                  key={result.player_id}
                  className="flex items-center justify-between gap-3 rounded-xl border border-white/10 bg-white/[0.03] px-4 py-3"
                >
                  <div className="min-w-0">
                    <p className="truncate text-sm font-bold text-white">{nameOf.get(result.player_id) ?? 'لاعب'}</p>
                    <p className={`mt-1 inline-flex items-center gap-1.5 text-xs font-bold ${OUTCOME_CLASS[outcome]}`}>
                      <OutcomeIcon outcome={outcome} />
                      {OUTCOME_TEXT[outcome]} · رهان {result.bet.toLocaleString('en-US')}
                    </p>
                  </div>
                  <span
                    className={`font-display text-base font-black tabular-nums ${
                      result.delta > 0 ? 'text-emerald-200' : result.delta < 0 ? 'text-rose-200' : 'text-ink-300'
                    }`}
                  >
                    {formatDelta(result.delta)}
                  </span>
                </li>
              );
            })}
          </ul>
        )}
      </div>
    </section>
  );
}
