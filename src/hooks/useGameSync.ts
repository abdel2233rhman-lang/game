import { useCallback, useEffect, useRef, useState } from 'react';
import { advanceGame, fetchGameState, type GameState } from '@/lib/gameApi';
import { getErrorMessage } from '@/lib/roomApi';
import { supabase } from '@/lib/supabase';

const TICK_MS = 250;
const ADVANCE_COOLDOWN_MS = 800;

export interface GameSync {
  state: GameState | null;
  nowMs: number;
  error: string | null;
  refresh: () => Promise<void>;
}

export function useGameSync(token: string, roomId: string): GameSync {
  const [state, setState] = useState<GameState | null>(null);
  const [nowMs, setNowMs] = useState(() => Date.now());
  const [error, setError] = useState<string | null>(null);

  const stateRef = useRef<GameState | null>(null);
  const offsetRef = useRef(0);
  const dirtyRef = useRef(false);
  const advancingRef = useRef(false);
  const lastAdvanceRef = useRef(0);

  const refresh = useCallback(async () => {
    try {
      const next = await fetchGameState(token);
      offsetRef.current = next.server_now_ms - Date.now();
      stateRef.current = next;
      setState(next);
      setError(null);
    } catch (err) {
      setError(getErrorMessage(err));
    }
  }, [token]);

  const gameId = state?.game?.id ?? null;

  useEffect(() => {
    void refresh();

    const markDirty = () => {
      dirtyRef.current = true;
      void refresh();
    };

    const channel = supabase
      .channel(`game:${roomId}:${gameId ?? 'none'}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'players', filter: `room_id=eq.${roomId}` }, markDirty)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'rooms', filter: `id=eq.${roomId}` }, markDirty);

    if (gameId) {
      channel.on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'game_events', filter: `game_id=eq.${gameId}` },
        markDirty,
      );
    }

    channel.subscribe((status) => {
      if (status === 'SUBSCRIBED') void refresh();
    });

    const handleVisible = () => {
      if (document.visibilityState === 'visible') void refresh();
    };
    document.addEventListener('visibilitychange', handleVisible);

    return () => {
      document.removeEventListener('visibilitychange', handleVisible);
      void supabase.removeChannel(channel);
    };
  }, [roomId, gameId, refresh]);

  useEffect(() => {
    const timer = window.setInterval(() => {
      const now = Date.now() + offsetRef.current;
      setNowMs(now);

      const current = stateRef.current;
      if (!current?.game || current.game.status === 'finished') return;

      const endsAt = current.game.phase_ends_at_ms;
      const expired = endsAt !== null && now >= endsAt;
      const cooledDown = Date.now() - lastAdvanceRef.current >= ADVANCE_COOLDOWN_MS;
      if (!(expired || dirtyRef.current) || advancingRef.current || !cooledDown) return;

      dirtyRef.current = false;
      advancingRef.current = true;
      lastAdvanceRef.current = Date.now();
      advanceGame(token)
        .catch((err: unknown) => setError(getErrorMessage(err)))
        .finally(() => {
          advancingRef.current = false;
          void refresh();
        });
    }, TICK_MS);

    return () => window.clearInterval(timer);
  }, [token, refresh]);

  return { state, nowMs, error, refresh };
}
