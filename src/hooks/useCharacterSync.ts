import { useCallback, useEffect, useRef, useState } from 'react';
import {
  advanceCharacterGame,
  characterHeartbeat,
  fetchCharacterState,
  type CharacterState,
} from '@/lib/characterApi';
import { getErrorMessage } from '@/lib/roomApi';
import { supabase } from '@/lib/supabase';

const TICK_MS = 250;
const ADVANCE_COOLDOWN_MS = 800;
const HEARTBEAT_MS = 15_000;
const SAFETY_REFRESH_MS = 6_000;

export interface CharacterSync {
  state: CharacterState | null;
  nowMs: number;
  error: string | null;
  refresh: () => Promise<void>;
}

/**
 * One source of truth for a Guess The Character room: the server state (char_get_state),
 * refreshed by Supabase Realtime events, a safety poll and tab-visibility changes.
 * All timers use the server clock (offset measured on every refresh) so every device ends a phase together.
 */
export function useCharacterSync(token: string, roomId: string): CharacterSync {
  const [state, setState] = useState<CharacterState | null>(null);
  const [nowMs, setNowMs] = useState(() => Date.now());
  const [error, setError] = useState<string | null>(null);

  const stateRef = useRef<CharacterState | null>(null);
  const offsetRef = useRef(0);
  const advancingRef = useRef(false);
  const lastAdvanceRef = useRef(0);
  const hintRefreshRef = useRef<number | null>(null);
  const refreshingRef = useRef(false);
  const queuedRef = useRef(false);

  const refresh = useCallback(async () => {
    if (refreshingRef.current) {
      queuedRef.current = true;
      return;
    }
    refreshingRef.current = true;
    try {
      const next = await fetchCharacterState(token);
      offsetRef.current = next.server_now_ms - Date.now();
      stateRef.current = next;
      setState(next);
      setError(null);
    } catch (err) {
      setError(getErrorMessage(err));
    } finally {
      refreshingRef.current = false;
      if (queuedRef.current) {
        queuedRef.current = false;
        void refresh();
      }
    }
  }, [token]);

  useEffect(() => {
    void refresh();

    const channel = supabase
      .channel(`character:${roomId}`)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'character_events', filter: `room_id=eq.${roomId}` }, () => void refresh())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'players', filter: `room_id=eq.${roomId}` }, () => void refresh())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'rooms', filter: `id=eq.${roomId}` }, () => void refresh())
      .subscribe((status) => {
        if (status === 'SUBSCRIBED') void refresh();
      });

    const handleVisible = () => {
      if (document.visibilityState === 'visible') void refresh();
    };
    const handleOnline = () => void refresh();
    document.addEventListener('visibilitychange', handleVisible);
    window.addEventListener('online', handleOnline);

    const safety = window.setInterval(() => void refresh(), SAFETY_REFRESH_MS);
    const beat = window.setInterval(() => {
      characterHeartbeat(token).catch(() => undefined);
    }, HEARTBEAT_MS);

    return () => {
      document.removeEventListener('visibilitychange', handleVisible);
      window.removeEventListener('online', handleOnline);
      window.clearInterval(safety);
      window.clearInterval(beat);
      void supabase.removeChannel(channel);
    };
  }, [roomId, token, refresh]);

  useEffect(() => {
    const timer = window.setInterval(() => {
      const now = Date.now() + offsetRef.current;
      setNowMs(now);

      const current = stateRef.current;
      if (!current) return;

      // A new hint becomes visible at a server-computed moment: fetch it right then.
      const hintAt = current.round?.next_hint_at_ms ?? null;
      if (current.game.phase === 'round' && hintAt !== null && now >= hintAt + 150 && hintRefreshRef.current !== hintAt) {
        hintRefreshRef.current = hintAt;
        void refresh();
      }

      const endsAt = current.game.phase_ends_at_ms;
      if (current.game.phase === 'setup' || current.game.phase === 'finished' || endsAt === null) return;
      const expired = now >= endsAt;
      const cooledDown = Date.now() - lastAdvanceRef.current >= ADVANCE_COOLDOWN_MS;
      if (!expired || advancingRef.current || !cooledDown) return;

      advancingRef.current = true;
      lastAdvanceRef.current = Date.now();
      advanceCharacterGame(token)
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
