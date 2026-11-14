import { useEffect, useRef, useState, type FormEvent } from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import { Check, HelpCircle, Loader2, Lock, Send, UserRound, X } from 'lucide-react';
import { CountdownRing } from '@/components/game/CountdownRing';
import { Feed, Leaderboard } from '@/components/character/CharacterBoard';
import { Button } from '@/components/ui/Button';
import {
  askCharacterQuestion,
  characterImageUrl,
  submitCharacterGuess,
  type CharacterState,
  type QuestionKey,
} from '@/lib/characterApi';
import { ANSWER_LABEL, CATEGORY_LABEL, HINT_POINTS, MODE_LABEL, QUESTIONS } from '@/lib/characterConstants';
import { secondsLeft } from '@/lib/gameTime';
import { getErrorMessage } from '@/lib/roomApi';
import { playSfx } from '@/lib/sfx';

interface Props {
  state: CharacterState;
  nowMs: number;
  token: string;
  onChanged: () => Promise<void>;
}

export function CountdownScreen({ state, nowMs }: Pick<Props, 'state' | 'nowMs'>) {
  const left = secondsLeft(state.game.phase_ends_at_ms, nowMs);
  const lastRef = useRef<number | null>(null);
  useEffect(() => {
    if (lastRef.current !== left) {
      lastRef.current = left;
      playSfx(left === 0 ? 'go' : 'tick');
    }
  }, [left]);

  return (
    <div className="mt-6 grid gap-6 lg:grid-cols-[1fr_340px]">
      <section className="glass flex min-h-[26rem] flex-col items-center justify-center gap-4 p-8 text-center">
        <p className="font-display text-sm font-bold tracking-[0.3em] text-gold-300">
          الجولة {state.game.round_number} من {state.game.total_rounds}
        </p>
        <AnimatePresence mode="wait">
          <motion.span
            key={left}
            initial={{ opacity: 0, scale: 0.4 }}
            animate={{ opacity: 1, scale: 1 }}
            exit={{ opacity: 0, scale: 1.8 }}
            transition={{ duration: 0.35 }}
            className="font-display text-8xl font-black gold-text sm:text-9xl"
          >
            {left > 0 ? left : 'GO!'}
          </motion.span>
        </AnimatePresence>
        <p className="text-ink-300">استعد... من هي الشخصية؟</p>
      </section>
      <aside>
        <Leaderboard players={state.players} showSolved={false} />
      </aside>
    </div>
  );
}

function CharacterCard({ state }: { state: CharacterState }) {
  const round = state.round!;
  const mode = state.game.mode;
  const total = Math.max(1, round.hints_total);
  const blur = mode === 'progressive' && total > 1 ? Math.round(24 * (1 - (round.hints_visible - 1) / (total - 1))) : 0;

  if (!round.show_image) {
    return (
      <div className="relative flex aspect-square w-full max-w-xs items-center justify-center overflow-hidden rounded-3xl border border-neon-400/40 bg-gradient-to-br from-ink-800 to-ink-950 shadow-neon">
        <span className="absolute inset-0 animate-glow-pulse bg-[radial-gradient(circle_at_50%_40%,rgba(168,85,247,0.35),transparent_65%)]" />
        <div className="relative flex flex-col items-center gap-2">
          <span className="font-display text-7xl font-black gold-text">؟</span>
          <span className="text-sm font-bold text-ink-200">وضع الغموض</span>
        </div>
      </div>
    );
  }

  return (
    <div className="relative aspect-square w-full max-w-xs overflow-hidden rounded-3xl border border-gold-400/40 bg-ink-800 shadow-gold">
      {round.image_path ? (
        <img
          src={characterImageUrl(round.image_path)}
          alt="صورة الشخصية"
          draggable={false}
          className="h-full w-full object-cover transition-[filter] duration-700"
          style={{ filter: blur > 0 ? `blur(${blur}px)` : undefined }}
        />
      ) : (
        <div className="flex h-full w-full flex-col items-center justify-center gap-2 bg-[radial-gradient(circle_at_50%_30%,rgba(245,197,66,0.18),transparent_70%)] text-ink-300">
          <UserRound className="h-24 w-24" strokeWidth={1.2} />
          <span className="text-xs font-bold">لا توجد صورة لهذه الشخصية</span>
        </div>
      )}
    </div>
  );
}

export function RoundScreen({ state, nowMs, token, onChanged }: Props) {
  const { game, round, me, players } = state;
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  const [flash, setFlash] = useState<{ ok: boolean; msg: string } | null>(null);
  const [asking, setAsking] = useState<QuestionKey | null>(null);
  const [error, setError] = useState<string | null>(null);
  const prevHints = useRef(round?.hints_visible ?? 0);
  const prevRound = useRef(round?.round_number);
  const tickRef = useRef<number | null>(null);

  const left = secondsLeft(game.phase_ends_at_ms, nowMs);

  useEffect(() => {
    if (!round) return;
    if (prevRound.current !== round.round_number) {
      prevRound.current = round.round_number;
      prevHints.current = round.hints_visible;
      setText('');
      setFlash(null);
      return;
    }
    if (round.hints_visible > prevHints.current) playSfx('hint');
    prevHints.current = round.hints_visible;
  }, [round]);

  useEffect(() => {
    if (left > 0 && left <= 5 && tickRef.current !== left) {
      tickRef.current = left;
      playSfx('tick');
    }
  }, [left]);

  if (!round) return null;

  const askedKeys = new Set(round.feed.flatMap((f) => (f.kind === 'question' ? [f.key] : [])));
  const answerByKey = new Map(round.feed.flatMap((f) => (f.kind === 'question' ? [[f.key, f.answer] as const] : [])));
  const canGuess = !me.solved && me.attempts_left > 0 && !busy && left > 0;
  const potential = HINT_POINTS[Math.min(round.hints_visible, HINT_POINTS.length) - 1] ?? HINT_POINTS[0];
  const bonus = game.mode === 'fast' ? 50 : 20;

  async function submit(event: FormEvent) {
    event.preventDefault();
    const value = text.trim();
    if (!value || !canGuess) return;
    setBusy(true);
    setError(null);
    try {
      const result = await submitCharacterGuess(token, value);
      if (result.correct) {
        const total = (result.points ?? 0) + (result.speed_bonus ?? 0);
        playSfx('correct');
        setFlash({ ok: true, msg: `إجابة صحيحة! +${total} نقطة${result.speed_bonus ? ` (منها ${result.speed_bonus} سرعة)` : ''}` });
      } else {
        playSfx('wrong');
        setFlash({ ok: false, msg: 'إجابة خاطئة. حاول مرة أخرى.' });
      }
      setText('');
      await onChanged();
    } catch (err) {
      playSfx('wrong');
      setError(getErrorMessage(err));
    } finally {
      setBusy(false);
    }
  }

  async function ask(key: QuestionKey) {
    setAsking(key);
    setError(null);
    try {
      await askCharacterQuestion(token, key);
      playSfx('reveal');
      await onChanged();
    } catch (err) {
      setError(getErrorMessage(err));
      await onChanged();
    } finally {
      setAsking(null);
    }
  }

  return (
    <>
      <div className="mt-6 flex flex-wrap items-center justify-between gap-3">
        <p className="font-display text-lg font-black text-white">
          الجولة {round.round_number} <span className="text-ink-400">من {game.total_rounds}</span>
        </p>
        <div className="flex flex-wrap gap-2 text-xs font-bold">
          <span className="rounded-full border border-white/15 px-3 py-1 text-ink-200">{CATEGORY_LABEL[round.category]}</span>
          <span className="rounded-full border border-neon-400/50 bg-neon-500/10 px-3 py-1 text-neon-300">{MODE_LABEL[game.mode]}</span>
        </div>
      </div>

      <div className="mt-6 grid gap-6 lg:grid-cols-[1fr_340px]">
        <div className="flex min-w-0 flex-col gap-6">
          <section className="glass flex flex-col items-center gap-6 p-6 md:flex-row md:items-start">
            <CharacterCard state={state} />
            <div className="flex w-full min-w-0 flex-1 flex-col gap-3">
              <div className="flex items-center justify-between gap-3">
                <h2 className="font-display text-sm font-bold tracking-[0.2em] text-white">التلميحات</h2>
                <span className="rounded-full border border-gold-400/40 bg-gold-500/10 px-3 py-1 text-xs font-bold text-gold-200">
                  الآن: {potential} نقطة{!me.solved && ` + ${bonus} للأسرع`}
                </span>
              </div>
              <ol className="flex flex-col gap-2">
                {Array.from({ length: round.hints_total }, (_, i) => {
                  const hint = round.hints[i];
                  return (
                    <motion.li
                      key={i}
                      initial={hint ? { opacity: 0, x: 16 } : false}
                      animate={{ opacity: 1, x: 0 }}
                      className={`flex items-center gap-3 rounded-xl border px-4 py-3 text-sm ${
                        hint ? 'border-neon-400/40 bg-neon-500/10 text-white' : 'border-white/10 bg-white/[0.02] text-ink-400'
                      }`}
                    >
                      <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-white/10 font-display text-xs font-bold">
                        {i + 1}
                      </span>
                      {hint ? <span className="flex-1 leading-[1.6]">{hint}</span> : (
                        <span className="flex flex-1 items-center gap-2">
                          <Lock className="h-3.5 w-3.5" /> تلميح مغلق
                        </span>
                      )}
                      <span className="shrink-0 font-display text-xs text-gold-300">{HINT_POINTS[i]}</span>
                    </motion.li>
                  );
                })}
              </ol>
            </div>
          </section>

          <section className="glass flex flex-col gap-4 p-6">
            {me.solved ? (
              <div className="flex items-center gap-3 rounded-xl border border-emerald-400/40 bg-emerald-500/10 px-4 py-4 text-emerald-100">
                <Check className="h-6 w-6" />
                <div>
                  <p className="font-bold">أصبت! حصلت على {me.round_points} نقطة في هذه الجولة.</p>
                  <p className="text-sm text-emerald-200/80">انتظر بقية اللاعبين...</p>
                </div>
              </div>
            ) : (
              <form onSubmit={submit} className="flex flex-col gap-3">
                <label htmlFor="guess" className="label !mb-0">
                  من هي الشخصية؟
                </label>
                <div className="flex gap-3">
                  <input
                    id="guess"
                    className="field"
                    value={text}
                    maxLength={80}
                    disabled={!canGuess && !busy}
                    placeholder="اكتب اسم الشخصية"
                    autoComplete="off"
                    onChange={(e) => setText(e.target.value)}
                  />
                  <Button type="submit" disabled={!canGuess || !text.trim()} icon={busy ? <Loader2 className="h-5 w-5 animate-spin" /> : <Send className="h-5 w-5 rtl:-scale-x-100" />}>
                    خمّن
                  </Button>
                </div>
                <div className="flex items-center gap-2 text-xs text-ink-300">
                  المحاولات المتبقية:
                  {[0, 1, 2].map((i) => (
                    <span key={i} className={`h-2.5 w-2.5 rounded-full ${i < me.attempts_left ? 'bg-neon-400' : 'bg-ink-600'}`} />
                  ))}
                </div>
              </form>
            )}
            <AnimatePresence>
              {flash && (
                <motion.p
                  key={flash.msg}
                  initial={{ opacity: 0, y: 6, scale: 0.97 }}
                  animate={{ opacity: 1, y: 0, scale: 1 }}
                  exit={{ opacity: 0 }}
                  role="status"
                  className={`flex items-center gap-2 rounded-xl border px-4 py-3 text-sm font-bold ${
                    flash.ok ? 'border-emerald-400/40 bg-emerald-500/10 text-emerald-100' : 'border-rose-400/40 bg-rose-500/10 text-rose-100'
                  }`}
                >
                  {flash.ok ? <Check className="h-4 w-4" /> : <X className="h-4 w-4" />}
                  {flash.msg}
                </motion.p>
              )}
            </AnimatePresence>
            {error && (
              <p role="alert" className="rounded-xl border border-amber-400/40 bg-amber-500/10 px-4 py-3 text-sm text-amber-100">
                {error}
              </p>
            )}
          </section>

          {game.questions_per_player > 0 && (
            <section className="glass flex flex-col gap-4 p-6">
              <div className="flex items-center justify-between gap-3">
                <h2 className="flex items-center gap-2 font-display text-sm font-bold tracking-[0.2em] text-white">
                  <HelpCircle className="h-4 w-4 text-neon-300" /> اسأل (نعم / لا)
                </h2>
                <span className="text-xs text-ink-300">أسئلتك المتبقية: <b className="text-gold-300">{me.questions_left}</b></span>
              </div>
              <div className="grid gap-2 sm:grid-cols-2">
                {QUESTIONS.map(({ key, label }) => {
                  const used = askedKeys.has(key);
                  const answer = answerByKey.get(key);
                  return (
                    <button
                      key={key}
                      type="button"
                      disabled={used || me.questions_left === 0 || me.solved || asking !== null || left <= 0}
                      onClick={() => void ask(key)}
                      className="flex items-center justify-between gap-2 rounded-xl border border-white/10 bg-white/[0.03] px-4 py-3 text-start text-sm transition enabled:hover:border-neon-400/60 enabled:hover:bg-neon-500/10 disabled:cursor-not-allowed disabled:opacity-60"
                    >
                      <span>{label}</span>
                      {asking === key && <Loader2 className="h-4 w-4 animate-spin" />}
                      {answer && (
                        <span className={`shrink-0 rounded-full px-2 py-0.5 text-xs font-bold ${answer === 'yes' ? 'bg-emerald-500/20 text-emerald-200' : answer === 'no' ? 'bg-rose-500/20 text-rose-200' : 'bg-white/10 text-ink-200'}`}>
                          {ANSWER_LABEL[answer]}
                        </span>
                      )}
                    </button>
                  );
                })}
              </div>
            </section>
          )}
        </div>

        <aside className="flex flex-col gap-6">
          <div className="glass flex items-center justify-center p-4">
            <CountdownRing endsAtMs={game.phase_ends_at_ms} nowMs={nowMs} totalSeconds={game.round_seconds} label="ثانية" />
          </div>
          <Leaderboard players={players} showSolved />
          <Feed items={round.feed} players={players} />
        </aside>
      </div>
    </>
  );
}
