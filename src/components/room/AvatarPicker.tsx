import { motion } from 'framer-motion';
import { AVATARS } from '@/lib/avatars';
import type { AvatarKey } from '@/types/room';

interface AvatarPickerProps {
  value: AvatarKey;
  onChange: (value: AvatarKey) => void;
}

export function AvatarPicker({ value, onChange }: AvatarPickerProps) {
  return (
    <div role="radiogroup" aria-label="اختر صورتك الرمزية" className="grid grid-cols-4 gap-3 sm:grid-cols-8">
      {AVATARS.map(({ key, label, Icon, gradient }) => {
        const selected = key === value;
        return (
          <motion.button
            key={key}
            type="button"
            role="radio"
            aria-checked={selected}
            aria-label={label}
            whileTap={{ scale: 0.92 }}
            onClick={() => onChange(key)}
            className={`relative flex aspect-square items-center justify-center rounded-2xl border transition duration-200 ${
              selected
                ? 'border-gold-300 bg-white/10 shadow-gold'
                : 'border-white/10 bg-white/[0.03] hover:border-neon-400/60'
            }`}
          >
            <span className={`flex h-10 w-10 items-center justify-center rounded-xl bg-gradient-to-br ${gradient} text-ink-950`}>
              <Icon className="h-5 w-5" />
            </span>
            {selected && (
              <motion.span
                layoutId="avatar-selected"
                className="absolute inset-0 rounded-2xl ring-2 ring-gold-300/80"
                transition={{ type: 'spring', stiffness: 400, damping: 30 }}
              />
            )}
          </motion.button>
        );
      })}
    </div>
  );
}
