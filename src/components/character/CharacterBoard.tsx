import { motion } from 'framer-motion';
import { Check, MessageCircleQuestion, X } from 'lucide-react';
import { AnimatedNumber } from '@/components/game/AnimatedNumber';
import { getAvatar } from '@/lib/avatars';
import type { CharacterPlayer, FeedItem } from '@/lib/characterApi';
import { ANSWER_LABEL, QUESTION_LABEL } from '@/lib/characterConstants';

export function Leaderboard({ players, showSolved }: { players: CharacterPlayer[]; showSolved: boolean }) {
  return (
    <section className="glass flex flex-col gap-4 p-5">
      <h2 className="font-display text-sm font-bold tracking-[0.2em] text-white">الترتيب المباشر</h2>
      <ol className="flex flex-col gap-2">
        {players.map((player, index) => {
          const { Icon, gradient } = getAvatar(player.avatar);
          return (
            <motion.li
              layout
              key={player.player_id}
              transition={{ type: 'spring', stiffness: 380, damping: 32 }}
              className={`flex items-center gap-3 rounded-xl border px-3 py-2.5 ${
                player.is_me ? 'border-neon-400/50 bg-neon-500/10' : 'border-white/10 bg-white/[0.03]'
              } ${showSolved && player.solved ? 'border-emerald-400/50 bg-emerald-500/10' : ''}`}
            >
              <span className="w-5 text-center font-display text-sm font-bold text-ink-300">{index + 1}</span>
              <span className="relative">
                <span className={`flex h-9 w-9 items-center justify-center rounded-lg bg-gradient-to-br ${gradient} text-ink-950`}>
                  <Icon className="h-5 w-5" />
                </span>
                <span
                  title={player.online ? 'متصل' : 'غير متصل'}
                  className={`absolute -bottom-0.5 -end-0.5 h-2.5 w-2.5 rounded-full border border-ink-900 ${
                    player.online ? 'bg-emerald-400' : 'bg-ink-500'
                  }`}
                />
              </span>
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-bold text-white">
                  {player.name}
                  {player.is_me && <span className="text-neon-300"> (أنت)</span>}
                </p>
                <p className="text-xs text-ink-400">
                  {showSolved && player.solved ? (
                    <span className="inline-flex items-center gap-1 text-emerald-300">
                      <Check className="h-3 w-3" /> خمّن الشخصية
                    </span>
                  ) : (
                    `صحيحة ${player.correct_count}`
                  )}
                </p>
              </div>
              <span className="font-display text-base font-black text-gold-300">
                <AnimatedNumber value={player.points} />
              </span>
            </motion.li>
          );
        })}
      </ol>
    </section>
  );
}

export function Feed({ items, players }: { items: FeedItem[]; players: CharacterPlayer[] }) {
  const nameOf = (id: string) => players.find((p) => p.player_id === id)?.name ?? 'لاعب';
  const recent = [...items].reverse();
  return (
    <section className="glass flex flex-col gap-3 p-5">
      <h2 className="font-display text-sm font-bold tracking-[0.2em] text-white">النشاط</h2>
      {recent.length === 0 ? (
        <p className="text-sm text-ink-400">لا نشاط بعد. كن أول من يخمّن!</p>
      ) : (
        <ul className="flex max-h-64 flex-col gap-2 overflow-y-auto pe-1 text-sm">
          {recent.map((item, index) => (
            <motion.li
              key={`${items.length - index}-${item.kind}-${item.player_id}`}
              initial={{ opacity: 0, y: -6 }}
              animate={{ opacity: 1, y: 0 }}
              className="flex items-start gap-2 text-ink-200"
            >
              {item.kind === 'guess' ? (
                item.correct ? (
                  <>
                    <Check className="mt-0.5 h-4 w-4 shrink-0 text-emerald-300" />
                    <span>
                      <b className="text-white">{nameOf(item.player_id)}</b> خمّن الشخصية الصحيحة 🎉
                    </span>
                  </>
                ) : (
                  <>
                    <X className="mt-0.5 h-4 w-4 shrink-0 text-rose-300" />
                    <span>
                      <b className="text-white">{nameOf(item.player_id)}</b> خمّن «{item.text}»
                    </span>
                  </>
                )
              ) : (
                <>
                  <MessageCircleQuestion className="mt-0.5 h-4 w-4 shrink-0 text-neon-300" />
                  <span>
                    <b className="text-white">{nameOf(item.player_id)}</b> سأل: {QUESTION_LABEL[item.key]}{' '}
                    <b className="text-gold-300">← {ANSWER_LABEL[item.answer]}</b>
                  </span>
                </>
              )}
            </motion.li>
          ))}
        </ul>
      )}
    </section>
  );
}
