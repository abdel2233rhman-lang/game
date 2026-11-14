import { useCallback, useEffect, useState } from 'react';
import { CharacterAdmin } from '@/components/admin/CharacterAdmin';
import { LandingPage } from '@/components/landing/LandingPage';
import { CreateRoomForm } from '@/components/room/CreateRoomForm';
import { JoinRoomForm } from '@/components/room/JoinRoomForm';
import { Lobby } from '@/components/room/Lobby';
import { Loader2 } from 'lucide-react';
import { getErrorMessage, resumeSession, type CreatedRoomSession } from '@/lib/roomApi';
import { clearStoredToken, getStoredToken, storeToken } from '@/lib/roomSession';
import type { RoomSession } from '@/types/room';

type Screen = 'landing' | 'create' | 'join' | 'lobby';

export default function App() {
  if (new URLSearchParams(window.location.search).get('admin') === 'characters') {
    return <CharacterAdmin />;
  }
  return <GameApp />;
}

function GameApp() {
  const [initialCode] = useState(() => new URLSearchParams(window.location.search).get('room') ?? '');
  const [screen, setScreen] = useState<Screen>(initialCode ? 'join' : 'landing');
  const [createVariant, setCreateVariant] = useState<'create' | 'friends'>('create');
  const [session, setSession] = useState<RoomSession | null>(null);
  const [restoring, setRestoring] = useState(!initialCode);
  const [notice, setNotice] = useState<string | null>(null);

  useEffect(() => {
    const token = getStoredToken();
    if (!token || initialCode) {
      setRestoring(false);
      return;
    }
    let cancelled = false;
    resumeSession(token)
      .then((restored) => {
        if (cancelled) return;
        if (restored) {
          setSession(restored);
          setScreen('lobby');
        } else {
          clearStoredToken();
        }
      })
      .catch((err: unknown) => {
        if (!cancelled) setNotice(getErrorMessage(err));
      })
      .finally(() => {
        if (!cancelled) setRestoring(false);
      });
    return () => {
      cancelled = true;
    };
  }, [initialCode]);

  const handleEntered = useCallback((created: CreatedRoomSession) => {
    storeToken(created.token);
    setSession(created);
    setScreen('lobby');
  }, []);

  const handleExit = useCallback((message?: string) => {
    clearStoredToken();
    setSession(null);
    setScreen('landing');
    setNotice(message ?? null);
  }, []);

  const goLanding = useCallback(() => setScreen('landing'), []);

  let content;
  if (restoring) {
    content = (
      <div className="flex min-h-screen items-center justify-center gap-3 text-ink-300">
        <Loader2 className="h-5 w-5 animate-spin text-neon-300" />
        جاري التحقق من جلستك...
      </div>
    );
  } else if (screen === 'lobby' && session) {
    content = <Lobby key={`${session.roomId}-${session.playerId}`} session={session} onExit={handleExit} />;
  } else if (screen === 'create') {
    content = <CreateRoomForm variant={createVariant} onCreated={handleEntered} onBack={goLanding} />;
  } else if (screen === 'join') {
    content = <JoinRoomForm initialCode={initialCode} onJoined={handleEntered} onBack={goLanding} />;
  } else {
    content = (
      <LandingPage
        onCreate={() => {
          setCreateVariant('create');
          setScreen('create');
        }}
        onJoin={() => setScreen('join')}
        onFriends={() => {
          setCreateVariant('friends');
          setScreen('create');
        }}
      />
    );
  }

  return (
    <>
      {content}
      {notice && (
        <div
          role="status"
          className="glass fixed bottom-4 left-1/2 z-[60] flex w-[calc(100%-2rem)] max-w-md -translate-x-1/2 items-center justify-between gap-4 px-5 py-4 text-sm text-ink-100 shadow-neon"
        >
          <span>{notice}</span>
          <button
            type="button"
            onClick={() => setNotice(null)}
            className="shrink-0 rounded-lg px-3 py-1 font-bold text-neon-300 transition hover:bg-white/5"
          >
            إغلاق
          </button>
        </div>
      )}
    </>
  );
}
