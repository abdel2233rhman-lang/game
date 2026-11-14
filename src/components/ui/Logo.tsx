import { Dices } from 'lucide-react';

interface LogoProps {
  size?: 'sm' | 'lg';
}

export function Logo({ size = 'sm' }: LogoProps) {
  const isLarge = size === 'lg';
  return (
    <div className="inline-flex items-center gap-3">
      <div
        className={`flex items-center justify-center rounded-xl border border-gold-400/40 bg-gradient-to-br from-neon-500/30 to-gold-500/20 shadow-neon ${
          isLarge ? 'h-14 w-14' : 'h-10 w-10'
        }`}
      >
        <Dices className={`${isLarge ? 'h-8 w-8' : 'h-5 w-5'} text-gold-300`} />
      </div>
      <span className={`font-display font-black tracking-[0.12em] ${isLarge ? 'text-5xl sm:text-7xl' : 'text-xl'}`}>
        <span className="text-white">RISK</span>{' '}
        <span className="gold-text">IT</span>
      </span>
    </div>
  );
}
