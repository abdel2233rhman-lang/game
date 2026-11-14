import type { ButtonHTMLAttributes, ReactNode } from 'react';

type ButtonVariant = 'primary' | 'gold' | 'ghost';

const VARIANT_CLASSES: Record<ButtonVariant, string> = {
  primary:
    'bg-gradient-to-r from-neon-500 to-electric-500 text-white shadow-neon hover:from-neon-400 hover:to-electric-400',
  gold: 'bg-gradient-to-r from-gold-300 to-gold-500 text-ink-950 shadow-gold hover:from-gold-200 hover:to-gold-400',
  ghost: 'border border-white/15 bg-white/[0.04] text-ink-100 hover:border-neon-400/60 hover:bg-white/[0.08]',
};

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant;
  icon?: ReactNode;
}

export function Button({ variant = 'primary', icon, className = '', children, disabled, ...props }: ButtonProps) {
  return (
    <button
      type="button"
      disabled={disabled}
      className={`inline-flex items-center justify-center gap-2 rounded-xl px-6 py-3 text-base font-bold tracking-wide transition duration-200 hover:-translate-y-0.5 active:translate-y-0 disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:translate-y-0 ${VARIANT_CLASSES[variant]} ${className}`}
      {...props}
    >
      {icon}
      {children}
    </button>
  );
}
