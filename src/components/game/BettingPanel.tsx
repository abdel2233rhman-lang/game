import { useState } from 'react';
import { Loader2, Lock } from 'lucide-react';
import { CountdownRing } from '@/components/game/CountdownRing';
import { Button } from '@/components/ui/Button';
import { placeBet, type GameState } from '@/lib/gameApi';
import { BETTING_SECONDS, BET_OPTIONS, CATEGORY_LABELS, DIFFICULTY_LABELS, DIFFICULTY_PAYOUT, DIFFICULTY_STYLES } from '@/lib/gameConstants';
import { getErrorMessage } from '@/lib/roomApi';
import { secondsLeft } from '@/lib/gameTime';

interface BettingPanelProps {
  state: GameState;
  nowMs: number;
  token: string;
  onChanged: () => Promise<void>;
}

const NO_BET = 0;

export function BettingPanel({ state, nowMs, token, onChanged }: BettingPanelProps) {
  const [selected, setSelected] = useState<number | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const { game, question, players, me } = state;
  if (!game || !question) return null;

  const balance = players.find((player) => player.is_me)?.balance ?? 0;
  const locked = me.bet !== null;
  const remaining = secondsLeft(game.phase_ends_at_ms, nowMs);
  const closed = remaining <= 0;
  const disabled = locked || closed || submitting;
  const lockedCount = players.filter((player) => player.locked).length;

  async function confirmBet() {
    if (selected === null) return;
    setSubmitting(true);
    setError(null);
    try {
      await placeBet(token, selected);
    } catch (err) {
      setError(getErrorMessage(err));
    } finally {
      setSubmitting(false);
      void onChanged();
    }
  }

  return (
    <section className="glass flex flex-col gap-6 p-5 sm:p-8">
      <div className="flex flex-wrap items-center justify-between gap-6">
        <div className="flex flex-col gap-3">
          <p className="text-sm font-bold text-ink-300">مرحلة الرهان</p>
          <h2 className="font-display text-2xl font-black text-white sm:text-3xl">ضع رهانك قبل السؤال</h2>
          <div className="flex flex-wrap gap-2">
            <span className="rounded-full border border-white/15 bg-white/5 px-3 py-1 text-xs font-bold text-ink-100">
              {CATEGORY_LABELS[question.category] ?? question.category}
            </span>
            <span className={`rounded-full border px-3 py-1 text-xs font-bold ${DIFFICULTY_STYLES[question.difficulty]}`}>
              {DIFFICULTY_LABELS[question.difficulty]} · الربح {DIFFICULTY_PAYOUT[question.difficulty]}
            </span>
          </div>
        </div>
        <CountdownRing endsAtMs={game.phase_ends_at_ms} nowMs={nowMs} totalSeconds={BETTING_SECONDS} label="ثانية" />
      </div>

      <div className="rounded-2xl border border-white/10 bg-white/[0.03] px-4 py-3 text-sm text-ink-200">
        رصيدك: <span className="font-display font-black text-gold-300 tabular-nums">{balance.toLocaleString('en-US')}</span>
      </div>

      {locked ? (
        <div className="flex flex-col items-center gap-3 rounded-2xl border border-neon-400/40 bg-neon-500/10 p-6 text-center">
          <Lock className="h-8 w-8 text-neon-200" />
          <p className="font-display text-xl font-black text-white">
            {me.bet === NO_BET ? 'اخترت عدم الرهان' : `راهنت بـ ${(me.bet ?? 0).toLocaleString('en-US')}`}
          </p>
          <p className="text-sm text-ink-300">
            بانتظار بقية اللاعبين ({lockedCount}/{players.length})
          </p>
        </div>
      ) : (
        <>
          <div>
            <span className="label">اختر قيمة الرهان</span>
            <div className="grid grid-cols-3 gap-3 sm:grid-cols-6">
              {BET_OPTIONS.map((amount) => {
                const tooHigh = amount > balance;
                const isSelected = selected === amount;
                return (
                  <button
                    key={amount}
                    type="button"
                    disabled={disabled || tooHigh}
                    aria-pressed={isSelected}
                    onClick={() => setSelected(amount)}
                    className={`rounded-xl border py-3 font-display text-base font-black tabular-nums transition duration-200 disabled:cursor-not-allowed disabled:opacity-35 ${
                      isSelected
                        ? 'border-gold-300 bg-gold-500/20 text-gold-200 shadow-gold'
                        : 'border-white/10 bg-white/[0.03] text-ink-100 enabled:hover:-translate-y-0.5 enabled:hover:border-gold-400/60'
                    }`}
                  >
                    {amount.toLocaleString('en-US')}
                  </button>
                );
              })}
            </div>
            <button
              type="button"
              disabled={disabled}
              aria-pressed={selected === NO_BET}
              onClick={() => setSelected(NO_BET)}
              className={`mt-3 w-full rounded-xl border py-2.5 text-sm font-bold transition duration-200 disabled:cursor-not-allowed disabled:opacity-35 ${
                selected === NO_BET
                  ? 'border-ink-300 bg-white/10 text-white'
                  : 'border-white/10 text-ink-300 enabled:hover:border-white/30'
              }`}
            >
              لا أراهن في هذه الجولة
            </button>
          </div>

          <div className="flex flex-col items-center gap-3">
            <Button
              variant="gold"
              onClick={confirmBet}
              disabled={selected === null || disabled}
              icon={submitting ? <Loader2 className="h-5 w-5 animate-spin" /> : <Lock className="h-5 w-5" />}
              className="w-full sm:w-auto"
            >
              تأكيد الرهان
            </Button>
            <p className="text-center text-xs text-ink-400">بعد التأكيد لا يمكن تغيير الرهان.</p>
          </div>
        </>
      )}

      {closed && !locked && (
        <p role="status" className="text-center text-sm text-amber-200">
          انتهى وقت الرهان، جاري الانتقال للسؤال.
        </p>
      )}

      {error && (
        <p role="alert" className="rounded-xl border border-red-400/40 bg-red-500/10 px-4 py-3 text-sm text-red-200">
          {error}
        </p>
      )}
    </section>
  );
}
