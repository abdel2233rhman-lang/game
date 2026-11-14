import { useState } from 'react';
import { HeroBackground } from '@/components/landing/HeroBackground';
import { HowToPlayModal } from '@/components/landing/HowToPlayModal';
import { LandingHero } from '@/components/landing/LandingHero';
import { LeaderboardModal } from '@/components/landing/LeaderboardModal';
import { PlayOptionsModal } from '@/components/landing/PlayOptionsModal';

interface LandingPageProps {
  onCreate: () => void;
  onJoin: () => void;
  onFriends: () => void;
}

export function LandingPage({ onCreate, onJoin, onFriends }: LandingPageProps) {
  const [playOpen, setPlayOpen] = useState(false);
  const [howToOpen, setHowToOpen] = useState(false);
  const [leaderboardOpen, setLeaderboardOpen] = useState(false);

  const choose = (action: () => void) => () => {
    setPlayOpen(false);
    action();
  };

  return (
    <div className="relative min-h-screen overflow-hidden">
      <HeroBackground />
      <LandingHero
        onPlay={() => setPlayOpen(true)}
        onHowToPlay={() => setHowToOpen(true)}
        onLeaderboard={() => setLeaderboardOpen(true)}
      />
      <PlayOptionsModal
        open={playOpen}
        onClose={() => setPlayOpen(false)}
        onCreate={choose(onCreate)}
        onJoin={choose(onJoin)}
        onFriends={choose(onFriends)}
      />
      <HowToPlayModal open={howToOpen} onClose={() => setHowToOpen(false)} />
      <LeaderboardModal open={leaderboardOpen} onClose={() => setLeaderboardOpen(false)} />
    </div>
  );
}
