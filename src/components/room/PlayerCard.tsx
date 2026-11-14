import { motion } from 'framer-motion';
import { Crown } from 'lucide-react';
import { getAvatar } from '@/lib/avatars';
import type { Player } from '@/types/room';

interface PlayerCardProps {
  player: Player;
  isMe: boolean;
}

export function PlayerCard({ player, isMe }: PlayerCardProps) {
  const { Icon, gradient } = getAvatar(player.avatar);
  return (
    <motion.li
      layout
      initial={{ opacity: 0, scale: 0.85, y: 12 }}
      animate={{ opacity: 1, scale: 1, y: 0 }}
      exit={{ opacity: 0, scale: 0.85 }}
      transition={{ type: 'spring', stiffness: 380, damping: 28 }}
      className={`glass relative flex flex-col items-center gap-3 p-5 text-center ${
        player.is_host ? 'border-gold-400/50 shadow-gold' : ''
      } ${isMe ? 'ring-2 ring-neon-400/70' : ''}`}
    >
      {player.is_host && (
        <span className="absolute -top-3 inline-flex items-center gap-1 rounded-full bg-gradient-to-r from-gold-300 to-gold-500 px-3 py-1 text-xs font-black text-ink-950">
          <Crown className="h-3 w-3" />
          HOST
        </span>
      )}
      <span className={`flex h-16 w-16 items-center justify-center rounded-2xl bg-gradient-to-br ${gradient} text-ink-950 shadow-lg`}>
        <Icon className="h-8 w-8" />
      </span>
      <div className="min-w-0 w-full">
        <p className="truncate font-bold text-white">{player.name}</p>
        <p className="mt-1 text-xs text-ink-400">{isMe ? 'أنت' : 'لاعب'}</p>
      </div>
    </motion.li>
  );
}

export function EmptySlot() {
  return (
    <li className="flex min-h-[10.5rem] flex-col items-center justify-center gap-2 rounded-2xl border border-dashed border-white/10 text-sm text-ink-400">
      <span className="h-2 w-2 animate-glow-pulse rounded-full bg-neon-400" />
      بانتظار لاعب
    </li>
  );
}
