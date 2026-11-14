import { useEffect } from 'react';
import { motion } from 'framer-motion';
import { Crown, Loader2, LogOut, RotateCcw, Zap } from 'lucide-react';
import { Confetti } from '@/components/game/FinalResults';
import { Button } from '@/components/ui/Button';
import { getAvatar } from '@/lib/avatars';
import type { CharacterPlayer } from '@/lib/characterApi';
import { playSfx } from '@/lib/sfx';

interface Props {
  players: CharacterPlayer[];
  isHost: boolean;
  busy: boolean;
  onPlayAgain: () => void;
  onLeave: () => void;
}

export function CharacterResults({ players, isHost, busy, onPlayAgain, onLeave }: Props) {
  const ranked = [...players].sort((a, b) => b.points - a.points);
  const top = ranked[0]?.points ?? 0;
  const winners = ranked.filter((p) => p.points === top);
  useEffect(() => playSfx('win'), []);

  const podium = ranked.slice(0, 3);
  const heights = ['h-44', 'h-32', 'h-24'];
  const order = podium.length === 3 ? [1, 0, 2] : podium.map((_, i) => i);

  return (
    <div className="relative mt-8">
      <Confetti />
      <div className="relative z-10 flex flex-col gap-6">
        <section className="glass flex flex-col items-center gap-3 p-8 text-center">
          <Crown className="h-10 w-10 text-gold-300" />
          <p className="text-sm font-bold text-ink-300">{winners.length > 1 ? 'تعادل بين' : 'بطل خمن الشخصية'}</p>
          <h2 className="font-display text-3xl font-black text-gold-200 sm:text-4xl">{winners.map((w) => w.name).join(' و ')}</h2>
          <p className="font-display text-lg font-bold text-white tabular-nums">{top.toLocaleString('en-US')} نقطة</p>
        </section>

        <section className="glass flex items-end justify-center gap-3 p-6 sm:gap-6">
          {order.map((idx) => {
            const p = podium[idx];
            const { Icon, gradient } = getAvatar(p.avatar);
            return (
              <motion.div
                key={p.player_id}
                initial={{ opacity: 0, y: 40 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.15 * (2 - idx) + 0.1, type: 'spring', stiffness: 200, damping: 20 }}
                className="flex w-24 flex-col items-center gap-2 sm:w-32"
              >
                <span className={`flex h-12 w-12 items-center justify-center rounded-xl bg-gradient-to-br ${gradient} text-ink-950`}>
                  <Icon className="h-6 w-6" />
                </span>
                <p className="w-full truncate text-center text-sm font-bold text-white">{p.name}</p>
                <div className={`flex w-full items-start justify-center rounded-t-xl border border-gold-400/40 bg-gradient-to-b from-gold-500/25 to-transparent pt-3 ${heights[idx]}`}>
                  <span className="font-display text-2xl font-black text-gold-200">{idx + 1}</span>
                </div>
              </motion.div>
            );
          })}
        </section>

        <section className="glass flex flex-col gap-3 p-6">
          <h2 className="font-display text-sm font-bold tracking-[0.2em] text-white">النتيجة النهائية</h2>
          <ol className="flex flex-col gap-2">
            {ranked.map((p, i) => {
              const { Icon, gradient } = getAvatar(p.avatar);
              return (
                <li key={p.player_id} className={`flex items-center gap-3 rounded-xl border px-4 py-3 ${p.is_me ? 'border-neon-400/50 bg-neon-500/10' : 'border-white/10 bg-white/[0.03]'}`}>
                  <span className="w-6 text-center font-display text-sm font-black text-gold-300">{i + 1}</span>
                  <span className={`flex h-10 w-10 items-center justify-center rounded-lg bg-gradient-to-br ${gradient} text-ink-950`}>
                    <Icon className="h-5 w-5" />
                  </span>
                  <div className="min-w-0 flex-1">
                    <p className="truncate font-bold text-white">{p.name}{p.is_me && <span className="text-neon-300"> (أنت)</span>}</p>
                    <p className="flex items-center gap-2 text-xs text-ink-400">
                      إجابات صحيحة {p.correct_count}
                      {p.fastest_count > 0 && (
                        <span className="inline-flex items-center gap-1 text-gold-300"><Zap className="h-3 w-3" /> الأسرع {p.fastest_count}×</span>
                      )}
                    </p>
                  </div>
                  <span className="font-display text-lg font-black text-gold-300 tabular-nums">{p.points.toLocaleString('en-US')}</span>
                </li>
              );
            })}
          </ol>
        </section>

        <div className="flex flex-col items-center justify-center gap-3 sm:flex-row">
          {isHost ? (
            <Button variant="gold" onClick={onPlayAgain} disabled={busy} icon={busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <RotateCcw className="h-4 w-4" />} className="w-full sm:w-auto">
              العب مرة أخرى في نفس الغرفة
            </Button>
          ) : (
            <p className="text-sm text-ink-400">بانتظار المضيف لإعادة اللعب.</p>
          )}
          <Button variant="ghost" onClick={onLeave} icon={<LogOut className="h-4 w-4" />} className="w-full sm:w-auto">
            الخروج من الغرفة
          </Button>
        </div>
      </div>
    </div>
  );
}
