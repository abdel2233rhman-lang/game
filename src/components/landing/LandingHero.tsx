import { motion } from 'framer-motion';
import { Medal, Users } from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { Logo } from '@/components/ui/Logo';

const STATS = [
  { value: '12', label: 'تصنيفًا للأسئلة' },
  { value: '4', label: 'مستويات صعوبة' },
  { value: '10', label: 'جولات في المباراة' },
  { value: '8', label: 'لاعبين كحد أقصى' },
];

interface LandingHeroProps {
  onPlay: () => void;
  onHowToPlay: () => void;
  onLeaderboard: () => void;
}

export function LandingHero({ onPlay, onHowToPlay, onLeaderboard }: LandingHeroProps) {
  return (
    <section className="relative z-10 mx-auto flex min-h-[calc(100vh-96px)] w-full max-w-6xl flex-col items-center justify-center px-4 py-16 text-center sm:px-6">
      <motion.div initial={{ opacity: 0, y: -12 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.6 }}>
        <Logo size="lg" />
      </motion.div>

      <motion.p
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 0.3, duration: 0.8 }}
        className="mt-6 font-display text-sm font-bold uppercase tracking-[0.35em] text-gold-300 sm:text-base"
      >
        Think Smart. Bet Big. Risk Everything.
      </motion.p>

      <motion.h1
        initial={{ opacity: 0, y: 16 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.45, duration: 0.7 }}
        className="mt-6 text-3xl font-black leading-[1.2] text-white sm:text-5xl"
      >
        الحظ ولا <span className="gold-text">الذكاء</span>؟
      </motion.h1>

      <motion.p
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 0.6, duration: 0.8 }}
        className="mt-4 max-w-2xl text-base leading-[1.5] text-ink-300 sm:text-lg"
      >
        لعبة جماعية تنافسية تجمع الذكاء والمخاطرة والرهانات وسرقة النقاط. راهن بذكاء، أجب بسرعة، وخلي أصحابك يندمون على الثقة فيك.
      </motion.p>

      <motion.div
        initial={{ opacity: 0, y: 12 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.75, duration: 0.6 }}
        className="mt-10 flex w-full flex-col items-stretch justify-center gap-3 sm:w-auto sm:flex-row sm:items-center"
      >
        <Button variant="primary" onClick={onPlay} className="px-10 py-4 text-lg">
          PLAY NOW
        </Button>
        <Button variant="ghost" onClick={onHowToPlay} className="py-4">
          HOW TO PLAY
        </Button>
        <Button variant="gold" onClick={onLeaderboard} icon={<Medal className="h-5 w-5" />} className="py-4">
          LEADERBOARD
        </Button>
      </motion.div>

      <motion.dl
        initial={{ opacity: 0, y: 16 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.9, duration: 0.6 }}
        className="mt-16 grid w-full grid-cols-2 gap-3 sm:grid-cols-4 sm:gap-4"
      >
        {STATS.map((stat) => (
          <div key={stat.label} className="glass group px-4 py-5 transition duration-300 hover:-translate-y-1 hover:border-gold-400/50">
            <dt className="text-sm text-ink-300">{stat.label}</dt>
            <dd className="mt-2 font-display text-3xl font-black gold-text">{stat.value}</dd>
          </div>
        ))}
      </motion.dl>

      <p className="mt-8 flex items-center gap-2 text-sm text-ink-400">
        <Users className="h-4 w-4 text-neon-300" />
        العب من الموبايل والكمبيوتر، والغرفة تتحدث مع الجميع لحظة بلحظة
      </p>
    </section>
  );
}
