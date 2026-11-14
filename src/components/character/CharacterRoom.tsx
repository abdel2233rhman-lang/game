import { useState } from 'react';
import { Loader2, LogOut, RefreshCw } from 'lucide-react';
import { CharacterLobby } from '@/components/character/CharacterLobby';
import { CharacterResults } from '@/components/character/CharacterResults';
import { RevealScreen } from '@/components/character/CharacterReveal';
import { CountdownScreen, RoundScreen } from '@/components/character/CharacterRound';
import { SoundToggle } from '@/components/character/SoundToggle';
import { ConnectionBadge } from '@/components/room/ConnectionBadge';
import { Button } from '@/components/ui/Button';
import { Logo } from '@/components/ui/Logo';
import type { ConnectionState } from '@/hooks/useRoomSync';
import { useCharacterSync } from '@/hooks/useCharacterSync';
import { nextCharacterRound, playCharacterAgain } from '@/lib/characterApi';
import { getErrorMessage, leaveRoom } from '@/lib/roomApi';
import type { RoomSession } from '@/types/room';

interface Props {
  session: RoomSession;
  connection: ConnectionState;
  onExit: (message?: string) => void;
}

export function CharacterRoom({ session, connection, onExit }: Props) {
  const { state, nowMs, error, refresh } = useCharacterSync(session.token, session.roomId);
  const [leaving, setLeaving] = useState(false);
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  async function handleLeave() {
    setLeaving(true);
    setActionError(null);
    try {
      await leaveRoom(session.token);
      onExit();
    } catch (err) {
      setActionError(getErrorMessage(err));
      setLeaving(false);
    }
  }

  async function run(action: () => Promise<void>) {
    setBusy(true);
    setActionError(null);
    try {
      await action();
      await refresh();
    } catch (err) {
      setActionError(getErrorMessage(err));
    } finally {
      setBusy(false);
    }
  }

  const header = (
    <header className="flex flex-wrap items-center justify-between gap-4">
      <div className="flex items-center gap-4">
        <Logo />
        <span className="hidden rounded-full border border-gold-400/40 bg-gold-500/10 px-3 py-1 text-xs font-bold text-gold-200 sm:inline">
          خمن الشخصية
        </span>
      </div>
      <div className="flex flex-wrap items-center gap-3">
        <SoundToggle />
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

  const shell = (children: React.ReactNode) => (
    <main className="relative z-10 mx-auto w-full max-w-6xl px-4 py-6 sm:px-6 sm:py-10">
      {header}
      {(error || actionError) && (
        <p role="alert" className="mt-6 rounded-xl border border-amber-400/40 bg-amber-500/10 px-4 py-3 text-sm text-amber-100">
          {actionError ?? error}
        </p>
      )}
      {children}
    </main>
  );

  if (!state) {
    return shell(
      <div className="mt-16 flex flex-col items-center gap-4 text-center text-ink-300">
        {error ? (
          <Button variant="ghost" onClick={() => void refresh()} icon={<RefreshCw className="h-4 w-4" />}>
            حاول مرة أخرى
          </Button>
        ) : (
          <p className="flex items-center gap-3">
            <Loader2 className="h-5 w-5 animate-spin text-neon-300" />
            جاري تحميل اللعبة...
          </p>
        )}
      </div>,
    );
  }

  const phase = state.game.phase;
  return shell(
    <>
      {phase === 'setup' && <CharacterLobby state={state} roomId={session.roomId} token={session.token} onChanged={refresh} />}
      {phase === 'countdown' && <CountdownScreen state={state} nowMs={nowMs} />}
      {phase === 'round' && <RoundScreen state={state} nowMs={nowMs} token={session.token} onChanged={refresh} />}
      {phase === 'reveal' && (
        <RevealScreen state={state} nowMs={nowMs} skipping={busy} onNext={() => void run(() => nextCharacterRound(session.token))} />
      )}
      {phase === 'finished' && (
        <CharacterResults
          players={state.players}
          isHost={state.me.is_host}
          busy={busy}
          onPlayAgain={() => void run(() => playCharacterAgain(session.token))}
          onLeave={handleLeave}
        />
      )}
    </>,
  );
}
