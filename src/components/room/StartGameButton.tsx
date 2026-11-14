import { useState } from 'react';
import { Loader2, Play } from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { startGame } from '@/lib/gameApi';
import { getErrorMessage } from '@/lib/roomApi';

interface StartGameButtonProps {
  token: string;
  playerCount: number;
  isHost: boolean;
}

export function StartGameButton({ token, playerCount, isHost }: StartGameButtonProps) {
  const [starting, setStarting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleStart() {
    setStarting(true);
    setError(null);
    try {
      await startGame(token);
    } catch (err) {
      setError(getErrorMessage(err));
      setStarting(false);
    }
  }

  if (!isHost) {
    return <p className="text-center text-sm text-ink-400">بانتظار المضيف لبدء المباراة.</p>;
  }

  return (
    <div className="flex flex-col items-center gap-3">
      <Button
        variant="gold"
        onClick={handleStart}
        disabled={starting || playerCount < 2}
        icon={starting ? <Loader2 className="h-5 w-5 animate-spin" /> : <Play className="h-5 w-5" />}
        className="w-full sm:w-auto"
      >
        ابدأ المباراة
      </Button>
      {playerCount < 2 && <p className="text-sm text-ink-400">تحتاج إلى لاعبين اثنين على الأقل.</p>}
      {error && (
        <p role="alert" className="rounded-xl border border-red-400/40 bg-red-500/10 px-4 py-3 text-sm text-red-200">
          {error}
        </p>
      )}
    </div>
  );
}
