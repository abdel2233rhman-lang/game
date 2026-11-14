import { motion } from 'framer-motion';
import { AnimatedNumber } from '@/components/game/AnimatedNumber';
import { getAvatar } from '@/lib/avatars';
import type { GamePlayer } from '@/lib/gameApi';

export function Standings({ players }: { players: GamePlayer[] }) {
  return (
    <section className="glass flex flex-col gap-4 p-5">
      <h2 className="font-display text-sm font-bold tracking-[0.2em] text-white">الترتيب</h2>
      <ol className="flex flex-col gap-2">
        {players.map((player, index) => {
          const { Icon, gradient } = getAvatar(player.avatar);
          const wrong = player.wrong_count + player.timeout_count;
          return (
            <motion.li
              layout
              key={player.player_id}
              transition={{ type: 'spring', stiffness: 380, damping: 32 }}
              className={`flex items-center gap-3 rounded-xl border px-3 py-2.5 ${
                player.is_me ? 'border-neon-400/50 bg-neon-500/10' : 'border-white/10 bg-white/[0.03]'
              }`}
            >
              <span className="w-6 text-center font-display text-sm font-bold text-ink-300">{index + 1}</span>
              <span className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-gradient-to-br ${gradient} text-ink-950`}>
                <Icon className="h-5 w-5" />
              </span>
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-bold text-white">
                  {player.name}
                  {player.is_me && <span className="text-neon-200"> (أنت)</span>}
                </p>
                <p className="text-xs text-ink-400">
                  صحيحة {player.correct_count} · خاطئة {wrong}
                </p>
              </div>
              <span className="font-display text-base font-black text-gold-300">
                <AnimatedNumber value={player.balance} />
              </span>
            </motion.li>
          );
        })}
      </ol>
    </section>
  );
}
