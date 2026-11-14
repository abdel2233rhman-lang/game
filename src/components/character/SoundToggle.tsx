import { useState } from 'react';
import { Volume2, VolumeX } from 'lucide-react';
import { isMuted, playSfx, setMuted } from '@/lib/sfx';

export function SoundToggle() {
  const [muted, setMutedState] = useState(isMuted);
  return (
    <button
      type="button"
      aria-label={muted ? 'تشغيل الصوت' : 'كتم الصوت'}
      aria-pressed={muted}
      onClick={() => {
        const next = !muted;
        setMuted(next);
        setMutedState(next);
        if (!next) playSfx('tick');
      }}
      className="inline-flex h-9 w-9 items-center justify-center rounded-full border border-white/15 bg-white/[0.04] text-ink-200 transition hover:border-neon-400/60 hover:text-white"
    >
      {muted ? <VolumeX className="h-4 w-4" /> : <Volume2 className="h-4 w-4" />}
    </button>
  );
}
