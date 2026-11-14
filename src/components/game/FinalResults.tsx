import { useState } from 'react';
import { motion } from 'framer-motion';
import { Crown, Loader2, LogOut } from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { getAvatar } from '@/lib/avatars';
import type { GamePlayer } from '@/lib/gameApi';

const CONFETTI_COLORS = ['#facc15', '#38bdf8', '#34d399', '#f472b6', '#fb923c', '#e2e8f0'];

interface ConfettiPiece {
  id: number;
  left: number;
  delay: number;
  duration: number;
  color: string;
  rotate: number;
}

function createConfetti(count: number): ConfettiPiece[] {
  return Array.from({ length: count }, (_, id) => ({
    id,
    left: Math.random() * 100,
    delay: Math.random() * 1.5,
    duration: 2.8 + Math.random() * 2,
    color: CONFETTI_COLORS[id % CONFETTI_COLORS.length],
    rotate: Math.random() * 360,
  }));
}

export function Confetti() {
  const [pieces] = useState(() => createConfetti(60));
  return (
    <div aria-hidden="true" className="pointer-events-none fixed inset-0 z-0 overflow-hidden">
      {pieces.map((piece) => (
        <motion.span
          key={piece.id}
          className="absolute top-0 block h-2.5 w-1.5 rounded-sm"
          style={{ left: `${piece.left}%`, backgroundColor: piece.color }}
          initial={{ y: -40, rotate: piece.rotate, opacity: 1 }}
          animate={{ y: '110vh', rotate: piece.rotate + 540, opacity: 0.9 }}
          transition={{ duration: piece.duration, delay: piece.delay, ease: 'easeIn', repeat: Infinity, repeatDelay: 1 }}
        />
      ))}
    </div>
  );
}

interface FinalResultsProps {
  players: GamePlayer[];
  onLeave: () => void;
  leaving: boolean;
}

export function FinalResults({ players, onLeave, leaving }: FinalResultsProps) {
  const ranked = [...players].sort((a, b) => b.balance - a.balance);
  const topBalance = ranked[0]?.balance ?? 0;
  const winners = ranked.filter((player) => player.balance === topBalance);
  const winnerNames = winners.map((player) => player.name).join(' و ');
  const winnerAvatar = winners.length === 1 ? getAvatar(winners[0].avatar) : null;
  const WinnerIcon = winnerAvatar?.Icon ?? Crown;

  return (
    <div className="relative mt-8">
      <Confetti />
      <div className="relative z-10 flex flex-col gap-6">
        <section className="glass flex flex-col items-center gap-4 p-8 text-center">
          <span
            className={`flex h-20 w-20 items-center justify-center rounded-3xl bg-gradient-to-br text-ink-950 shadow-gold ${
              winnerAvatar?.gradient ?? 'from-gold-300 to-gold-600'
            }`}
          >
            <WinnerIcon className="h-10 w-10" />
          </span>
          <p className="text-sm font-bold text-ink-300">{winners.length > 1 ? 'تعادل بين' : 'الفائز'}</p>
          <h2 className="font-display text-3xl font-black text-gold-200 sm:text-4xl">{winnerNames || 'لا يوجد فائز'}</h2>
          <p className="font-display text-lg font-bold text-white tabular-nums">{topBalance.toLocaleString('en-US')} نقطة</p>
        </section>

        <div className="flex flex-col gap-6">
          <section className="glass flex flex-col gap-4 p-6">
            <h2 className="font-display text-sm font-bold tracking-[0.2em] text-white">النتيجة النهائية</h2>
            <ol className="flex flex-col gap-3">
              {ranked.map((player, index) => {
                const { Icon, gradient } = getAvatar(player.avatar);
                return (
                  <li key={player.player_id} className="flex items-center gap-3 rounded-xl border border-white/10 bg-white/[0.03] px-4 py-3">
                    <span className="w-6 text-center font-display text-sm font-black text-gold-300">{index + 1}</span>
                    <span className={`flex h-10 w-10 items-center justify-center rounded-lg bg-gradient-to-br ${gradient} text-ink-950`}>
                      <Icon className="h-5 w-5" />
                    </span>
                    <div className="min-w-0 flex-1">
                      <p className="truncate font-bold text-white">{player.name}</p>
                      <p className="text-xs text-ink-400">
                        صحيحة {player.correct_count} · خاطئة {player.wrong_count} · بدون إجابة {player.timeout_count}
                      </p>
                    </div>
                    <span className="font-display text-lg font-black text-gold-300 tabular-nums">
                      {player.balance.toLocaleString('en-US')}
                    </span>
                  </li>
                );
              })}
            </ol>
          </section>

          <div className="flex justify-center">
            <Button
              variant="ghost"
              onClick={onLeave}
              disabled={leaving}
              icon={leaving ? <Loader2 className="h-4 w-4 animate-spin" /> : <LogOut className="h-4 w-4" />}
              className="w-full sm:w-auto"
            >
              الخروج من الغرفة
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
}
