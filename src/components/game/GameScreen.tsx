import { useState } from 'react';
import { Loader2, LogOut, RefreshCw } from 'lucide-react';
import { BettingPanel } from '@/components/game/BettingPanel';
import { FinalResults } from '@/components/game/FinalResults';
import { QuestionPanel } from '@/components/game/QuestionPanel';
import { RevealPanel } from '@/components/game/RevealPanel';
import { Standings } from '@/components/game/Standings';
import { ConnectionBadge } from '@/components/room/ConnectionBadge';
import { Button } from '@/components/ui/Button';
import { Logo } from '@/components/ui/Logo';
import type { ConnectionState } from '@/hooks/useRoomSync';
import { useGameSync } from '@/hooks/useGameSync';
import { CATEGORY_LABELS, DIFFICULTY_LABELS, DIFFICULTY_STYLES } from '@/lib/gameConstants';
import { getErrorMessage, leaveRoom } from '@/lib/roomApi';
import type { RoomSession } from '@/types/room';

interface GameScreenProps {
  session: RoomSession;
  connection: ConnectionState;
  onExit: (message?: string) => void;
}

export function GameScreen({ session, connection, onExit }: GameScreenProps) {
  const { state, nowMs, error, refresh } = useGameSync(session.token, session.roomId);
  const [leaving, setLeaving] = useState(false);
  const [leaveError, setLeaveError] = useState<string | null>(null);

  async function handleLeave() {
    setLeaving(true);
    setLeaveError(null);
    try {
      await leaveRoom(session.token);
      onExit();
    } catch (err) {
      setLeaveError(getErrorMessage(err));
      setLeaving(false);
    }
  }

  const header = (
    <header className="flex flex-wrap items-center justify-between gap-4">
      <Logo />
      <div className="flex flex-wrap items-center gap-3">
        <ConnectionBadge state={connection} />
        <Button
          variant="ghost"
          onClick={handleLeave}
          disabled={leaving}
          icon={leaving ? <Loader2 className="h-4 w-4 animate-spin" /> : <LogOut className="h-4 w-4" />}
          className="px-4 py-2 text-sm"
        >
          غادر الغرفة
        </Button>
      </div>
    </header>
  );

  if (!state) {
    return (
      <main className="relative z-10 mx-auto w-full max-w-6xl px-4 py-6 sm:px-6 sm:py-10">
        {header}
        <div className="mt-16 flex flex-col items-center gap-4 text-center text-ink-300">
          {error ? (
            <>
              <p role="alert">{error}</p>
              <Button variant="ghost" onClick={() => void refresh()} icon={<RefreshCw className="h-4 w-4" />}>
                حاول مرة أخرى
              </Button>
            </>
          ) : (
            <p className="flex items-center gap-3">
              <Loader2 className="h-5 w-5 animate-spin text-neon-300" />
              جاري تحميل المباراة...
            </p>
          )}
        </div>
      </main>
    );
  }

  const { game, question, players } = state;
  const finished = game?.phase === 'finished';

  return (
    <main className="relative z-10 mx-auto w-full max-w-6xl px-4 py-6 sm:px-6 sm:py-10">
      {header}

      {game && question && !finished && (
        <div className="mt-6 flex flex-wrap items-center justify-between gap-3">
          <p className="font-display text-lg font-black text-white">
            الجولة {game.round_number} <span className="text-ink-400">من {game.total_rounds}</span>
          </p>
          <div className="flex flex-wrap gap-2 text-xs font-bold">
            <span className="rounded-full border border-white/15 px-3 py-1 text-ink-200">
              {CATEGORY_LABELS[question.category] ?? question.category}
            </span>
            <span className={`rounded-full border px-3 py-1 ${DIFFICULTY_STYLES[question.difficulty]}`}>
              {DIFFICULTY_LABELS[question.difficulty]}
            </span>
          </div>
        </div>
      )}

      {(error || leaveError) && (
        <p role="alert" className="mt-6 rounded-xl border border-amber-400/40 bg-amber-500/10 px-4 py-3 text-sm text-amber-100">
          {leaveError ?? error}
        </p>
      )}

      {finished ? (
        <FinalResults players={players} onLeave={handleLeave} leaving={leaving} />
      ) : (
        <div className="mt-6 grid gap-6 lg:grid-cols-[1fr_340px]">
          <div className="min-w-0">
            {game?.phase === 'betting' && <BettingPanel state={state} nowMs={nowMs} token={session.token} onChanged={refresh} />}
            {game?.phase === 'question' && <QuestionPanel state={state} nowMs={nowMs} token={session.token} onChanged={refresh} />}
            {game?.phase === 'reveal' && <RevealPanel state={state} nowMs={nowMs} />}
            {!game && (
              <p className="glass p-8 text-center text-ink-300">جاري تجهيز الجولة الأولى...</p>
            )}
          </div>
          <aside>
            <Standings players={players} />
          </aside>
        </div>
      )}
    </main>
  );
}
