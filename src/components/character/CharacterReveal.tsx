import { useEffect } from 'react';
import { motion } from 'framer-motion';
import { Check, Loader2, SkipForward, X } from 'lucide-react';
import { Leaderboard } from '@/components/character/CharacterBoard';
import { Button } from '@/components/ui/Button';
import { getAvatar } from '@/lib/avatars';
import { characterImageUrl, type CharacterState } from '@/lib/characterApi';
import { CATEGORY_LABEL } from '@/lib/characterConstants';
import { secondsLeft } from '@/lib/gameTime';
import { playSfx } from '@/lib/sfx';

interface Props {
  state: CharacterState;
  nowMs: number;
  onNext: () => void;
  skipping: boolean;
}

export function RevealScreen({ state, nowMs, onNext, skipping }: Props) {
  const { game, round, reveal, players, me } = state;
  const roundNumber = round?.round_number;
  const mine = reveal?.results.find((r) => r.player_id === me.player_id);

  useEffect(() => {
    playSfx(mine?.solved ? 'win' : 'reveal');
  }, [roundNumber, mine?.solved]);

  if (!round || !reveal) return null;
  const left = secondsLeft(game.phase_ends_at_ms, nowMs);
  const isLast = game.round_number >= game.total_rounds;

  return (
    <div className="mt-6 grid gap-6 lg:grid-cols-[1fr_340px]">
      <div className="flex min-w-0 flex-col gap-6">
        <motion.section
          initial={{ opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          className="glass flex flex-col items-center gap-5 p-6 text-center sm:p-8"
        >
          <p className="text-xs font-bold tracking-[0.3em] text-ink-300">
            الجولة {game.round_number} من {game.total_rounds} · {CATEGORY_LABEL[round.category]}
          </p>
          {round.image_path && (
            <img
              src={characterImageUrl(round.image_path)}
              alt={reveal.name}
              className="h-44 w-44 rounded-3xl border border-gold-400/50 object-cover shadow-gold"
            />
          )}
          <p className="text-sm text-ink-300">الشخصية كانت</p>
          <motion.h2
            initial={{ scale: 0.6, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            transition={{ type: 'spring', stiffness: 260, damping: 18 }}
            className="font-display text-4xl font-black gold-text sm:text-5xl"
          >
            {reveal.name}
          </motion.h2>
          <ol className="mt-2 flex w-full max-w-xl flex-col gap-2 text-start">
            {round.hints.map((hint, i) => (
              <li key={i} className="flex items-center gap-3 rounded-xl border border-white/10 bg-white/[0.03] px-4 py-2.5 text-sm text-ink-100">
                <span className="flex h-6 w-6 items-center justify-center rounded-full bg-white/10 font-display text-xs font-bold">{i + 1}</span>
                {hint}
              </li>
            ))}
          </ol>
        </motion.section>

        <section className="glass flex flex-col gap-4 p-6">
          <h2 className="font-display text-sm font-bold tracking-[0.2em] text-white">نتيجة الجولة</h2>
          <ul className="flex flex-col gap-2">
            {reveal.results.map((res) => {
              const p = players.find((x) => x.player_id === res.player_id);
              if (!p) return null;
              const { Icon, gradient } = getAvatar(p.avatar);
              return (
                <li key={res.player_id} className="flex items-center gap-3 rounded-xl border border-white/10 bg-white/[0.03] px-4 py-3">
                  <span className={`flex h-9 w-9 items-center justify-center rounded-lg bg-gradient-to-br ${gradient} text-ink-950`}>
                    <Icon className="h-5 w-5" />
                  </span>
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-bold text-white">
                      {p.name}
                      {p.is_me && <span className="text-neon-300"> (أنت)</span>}
                    </p>
                    <p className="text-xs text-ink-400">
                      {res.solved
                        ? `خمّن بعد ${((res.elapsed_ms ?? 0) / 1000).toFixed(1)}ث · ${res.hints_visible} تلميح${res.speed_bonus ? ` · سرعة +${res.speed_bonus}` : ''}`
                        : 'لم يخمّن'}
                    </p>
                  </div>
                  {res.solved ? <Check className="h-5 w-5 text-emerald-300" /> : <X className="h-5 w-5 text-rose-300" />}
                  <span className="w-14 text-end font-display text-base font-black text-gold-300">+{res.points}</span>
                </li>
              );
            })}
          </ul>
          <div className="flex flex-wrap items-center justify-between gap-3 border-t border-white/10 pt-4">
            <p className="text-sm text-ink-300">
              {isLast ? 'النتيجة النهائية' : 'الجولة التالية'} بعد <b className="font-display text-white">{left}</b> ث
            </p>
            {me.is_host ? (
              <Button
                variant="gold"
                onClick={onNext}
                disabled={skipping}
                icon={skipping ? <Loader2 className="h-4 w-4 animate-spin" /> : <SkipForward className="h-4 w-4" />}
                className="px-5 py-2 text-sm"
              >
                {isLast ? 'عرض النتيجة' : 'ابدأ الجولة التالية'}
              </Button>
            ) : (
              <span className="text-xs text-ink-400">المضيف يستطيع تخطي الانتظار.</span>
            )}
          </div>
        </section>
      </div>
      <aside>
        <Leaderboard players={players} showSolved={false} />
      </aside>
    </div>
  );
}
