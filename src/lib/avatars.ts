import { Bot, Crown, Flame, Gem, Ghost, Rocket, Target, Zap, type LucideIcon } from 'lucide-react';
import type { AvatarKey } from '@/types/room';

export interface AvatarOption {
  key: AvatarKey;
  label: string;
  Icon: LucideIcon;
  gradient: string;
}

export const AVATARS: AvatarOption[] = [
  { key: 'crown', label: 'الملك', Icon: Crown, gradient: 'from-gold-300 to-gold-600' },
  { key: 'rocket', label: 'الصاروخ', Icon: Rocket, gradient: 'from-neon-400 to-electric-500' },
  { key: 'zap', label: 'البرق', Icon: Zap, gradient: 'from-yellow-300 to-orange-500' },
  { key: 'flame', label: 'اللهب', Icon: Flame, gradient: 'from-orange-400 to-red-600' },
  { key: 'ghost', label: 'الشبح', Icon: Ghost, gradient: 'from-slate-300 to-slate-600' },
  { key: 'bot', label: 'الروبوت', Icon: Bot, gradient: 'from-cyan-300 to-sky-600' },
  { key: 'target', label: 'الهدف', Icon: Target, gradient: 'from-rose-400 to-pink-700' },
  { key: 'gem', label: 'الجوهرة', Icon: Gem, gradient: 'from-emerald-300 to-teal-600' },
];

export function getAvatar(key: AvatarKey): AvatarOption {
  return AVATARS.find((avatar) => avatar.key === key) ?? AVATARS[0];
}
