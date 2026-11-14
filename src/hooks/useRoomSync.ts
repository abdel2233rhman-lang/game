import { useCallback, useEffect, useState } from 'react';
import { fetchRoomSnapshot } from '@/lib/roomApi';
import { supabase } from '@/lib/supabase';
import type { Player, Room } from '@/types/room';

export type ConnectionState = 'connecting' | 'live' | 'offline';

export interface RoomSync {
  room: Room | null;
  players: Player[];
  connection: ConnectionState;
  loaded: boolean;
  error: string | null;
  refresh: () => Promise<void>;
}

export function useRoomSync(roomId: string): RoomSync {
  const [room, setRoom] = useState<Room | null>(null);
  const [players, setPlayers] = useState<Player[]>([]);
  const [connection, setConnection] = useState<ConnectionState>('connecting');
  const [loaded, setLoaded] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    try {
      const snapshot = await fetchRoomSnapshot(roomId);
      setRoom(snapshot.room);
      setPlayers(snapshot.players);
      setError(null);
    } catch {
      setError('تعذر تحديث الغرفة. سنعيد المحاولة تلقائيًا.');
    } finally {
      setLoaded(true);
    }
  }, [roomId]);

  useEffect(() => {
    void refresh();

    const channel = supabase
      .channel(`room:${roomId}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'players', filter: `room_id=eq.${roomId}` },
        () => void refresh(),
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'rooms', filter: `id=eq.${roomId}` },
        () => void refresh(),
      )
      .subscribe((status) => {
        if (status === 'SUBSCRIBED') {
          setConnection('live');
          void refresh();
        } else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
          setConnection('offline');
        } else if (status === 'CLOSED') {
          setConnection('connecting');
        }
      });

    const handleOffline = () => setConnection('offline');
    const handleOnline = () => {
      setConnection('connecting');
      void refresh();
    };
    const handleVisible = () => {
      if (document.visibilityState === 'visible') void refresh();
    };

    window.addEventListener('offline', handleOffline);
    window.addEventListener('online', handleOnline);
    document.addEventListener('visibilitychange', handleVisible);

    return () => {
      window.removeEventListener('offline', handleOffline);
      window.removeEventListener('online', handleOnline);
      document.removeEventListener('visibilitychange', handleVisible);
      void supabase.removeChannel(channel);
    };
  }, [roomId, refresh]);

  return { room, players, connection, loaded, error, refresh };
}
