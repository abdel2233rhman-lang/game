import { useEffect, useState } from 'react';
import { AnimatePresence } from 'framer-motion';
import { Loader2, LogOut, RefreshCw } from 'lucide-react';
import { ConnectionBadge } from '@/components/room/ConnectionBadge';
import { EmptySlot, PlayerCard } from '@/components/room/PlayerCard';
import { InvitePanel } from '@/components/room/InvitePanel';
import { RoomSettingsPanel } from '@/components/room/RoomSettingsPanel';
import { StartGameButton } from '@/components/room/StartGameButton';
import { CharacterRoom } from '@/components/character/CharacterRoom';
import { GameScreen } from '@/components/game/GameScreen';
import { Button } from '@/components/ui/Button';
import { Logo } from '@/components/ui/Logo';
import { useRoomSync } from '@/hooks/useRoomSync';
import { getErrorMessage, leaveRoom } from '@/lib/roomApi';
import type { RoomSession } from '@/types/room';

interface LobbyProps {
  session: RoomSession;
  onExit: (message?: string) => void;
}

export function Lobby({ session, onExit }: LobbyProps) {
  const { room, players, connection, loaded, error, refresh } = useRoomSync(session.roomId);
  const [leaving, setLeaving] = useState(false);
  const [leaveError, setLeaveError] = useState<string | null>(null);

  const me = players.find((player) => player.id === session.playerId);

  useEffect(() => {
    if (!loaded || error) return;
    if (!room) onExit('أُغلقت الغرفة لأن جميع اللاعبين غادروها.');
    else if (!me) onExit('تمت إزالتك من الغرفة.');
  }, [loaded, error, room, me, onExit]);

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

  if (!loaded) {
    return (
      <div className="flex min-h-screen items-center justify-center gap-3 text-ink-300">
        <Loader2 className="h-5 w-5 animate-spin text-neon-300" />
        جاري تحميل الغرفة...
      </div>
    );
  }

  if (!room) {
    return (
      <div className="mx-auto flex min-h-screen max-w-md flex-col items-center justify-center gap-4 px-4 text-center">
        <p role="alert" className="text-ink-200">{error ?? 'تعذر تحميل الغرفة.'}</p>
        <Button variant="ghost" onClick={() => void refresh()} icon={<RefreshCw className="h-4 w-4" />}>
          حاول مرة أخرى
        </Button>
      </div>
    );
  }

  if (room.game_type === 'guess_character') {
    return <CharacterRoom session={session} connection={connection} onExit={onExit} />;
  }

  if (room.status !== 'lobby') {
    return <GameScreen session={session} connection={connection} onExit={onExit} />;
  }

  const emptySlots = Math.max(0, room.max_players - players.length);

  return (
    <main className="relative z-10 mx-auto w-full max-w-6xl px-4 py-6 sm:px-6 sm:py-10">
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

      {(error || leaveError) && (
        <p role="alert" className="mt-6 rounded-xl border border-amber-400/40 bg-amber-500/10 px-4 py-3 text-sm text-amber-100">
          {leaveError ?? error}
        </p>
      )}

      <div className="mt-8 grid gap-6 lg:grid-cols-[1fr_340px]">
        <section>
          <div className="flex items-end justify-between gap-4">
            <h1 className="font-display text-2xl font-black tracking-wider text-white sm:text-3xl">اللاعبون</h1>
            <span className="font-display text-lg font-bold text-gold-300">
              {players.length}/{room.max_players}
            </span>
          </div>

          <ul className="mt-6 grid grid-cols-2 gap-4 md:grid-cols-3 xl:grid-cols-4">
            <AnimatePresence initial={false}>
              {players.map((player) => (
                <PlayerCard key={player.id} player={player} isMe={player.id === session.playerId} />
              ))}
            </AnimatePresence>
            {Array.from({ length: emptySlots }, (_, index) => (
              <EmptySlot key={`empty-${index}`} />
            ))}
          </ul>

          <div className="mt-8 flex flex-col items-center gap-4">
            <StartGameButton token={session.token} playerCount={players.length} isHost={me?.is_host ?? false} />
            <p className="text-center text-sm text-ink-400">الغرفة تتحدث لحظة بلحظة.</p>
          </div>
        </section>

        <aside className="flex flex-col gap-6">
          <InvitePanel code={room.code} />
          <RoomSettingsPanel
            room={room}
            playerCount={players.length}
            token={session.token}
            isHost={me?.is_host ?? false}
            onSaved={refresh}
          />
        </aside>
      </div>
    </main>
  );
}
