import { useState } from 'react';
import { Loader2 } from 'lucide-react';
import { setQuestionSeconds } from '@/lib/gameApi';
import { QUESTION_SECONDS_OPTIONS } from '@/lib/gameConstants';
import { getErrorMessage, updateRoomSettings } from '@/lib/roomApi';
import type { GameMode, Room } from '@/types/room';

const PLAYER_OPTIONS = [2, 3, 4, 5, 6, 7, 8];

const MODE_LABELS: Record<GameMode, string> = {
  solo: 'SOLO',
  team: 'TEAM',
};

interface RoomSettingsPanelProps {
  room: Room;
  playerCount: number;
  token: string;
  isHost: boolean;
  onSaved: () => Promise<void>;
}

export function RoomSettingsPanel({ room, playerCount, token, isHost, onSaved }: RoomSettingsPanelProps) {
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function save(action: () => Promise<void>) {
    setSaving(true);
    setError(null);
    try {
      await action();
      await onSaved();
    } catch (err) {
      setError(getErrorMessage(err));
    } finally {
      setSaving(false);
    }
  }

  function update(next: { maxPlayers: number; gameMode: GameMode }) {
    return save(() => updateRoomSettings({ token, ...next }));
  }

  return (
    <section className="glass flex flex-col gap-6 p-6">
      <header className="flex items-center justify-between gap-3">
        <h2 className="font-display text-sm font-bold tracking-[0.2em] text-white">إعدادات الغرفة</h2>
        {saving && <Loader2 className="h-4 w-4 animate-spin text-neon-300" />}
      </header>

      <div>
        <span className="label">عدد اللاعبين</span>
        <div className="grid grid-cols-7 gap-2">
          {PLAYER_OPTIONS.map((count) => {
            const selected = room.max_players === count;
            const blocked = count < playerCount;
            return (
              <button
                key={count}
                type="button"
                disabled={!isHost || saving || blocked}
                aria-pressed={selected}
                onClick={() => update({ maxPlayers: count, gameMode: room.game_mode })}
                className={`rounded-lg border py-2 font-display text-sm font-bold transition duration-200 disabled:cursor-not-allowed disabled:opacity-40 ${
                  selected
                    ? 'border-gold-300 bg-gold-500/15 text-gold-200'
                    : 'border-white/10 bg-white/[0.03] text-ink-300 enabled:hover:border-neon-400/60 enabled:hover:text-white'
                }`}
              >
                {count}
              </button>
            );
          })}
        </div>
      </div>

      <div>
        <span className="label">نظام اللعب</span>
        <div className="grid grid-cols-2 gap-2">
          {(Object.keys(MODE_LABELS) as GameMode[]).map((mode) => {
            const selected = room.game_mode === mode;
            return (
              <button
                key={mode}
                type="button"
                disabled={!isHost || saving}
                aria-pressed={selected}
                onClick={() => update({ maxPlayers: room.max_players, gameMode: mode })}
                className={`rounded-xl border py-3 font-display text-sm font-bold tracking-wider transition duration-200 disabled:cursor-not-allowed disabled:opacity-40 ${
                  selected
                    ? 'border-neon-400 bg-neon-500/15 text-white shadow-neon'
                    : 'border-white/10 bg-white/[0.03] text-ink-300 enabled:hover:border-neon-400/60 enabled:hover:text-white'
                }`}
              >
                {MODE_LABELS[mode]}
              </button>
            );
          })}
        </div>
      </div>

      <div>
        <span className="label">وقت كل سؤال (ثانية)</span>
        <div className="grid grid-cols-3 gap-2 sm:grid-cols-6">
          {QUESTION_SECONDS_OPTIONS.map((seconds) => {
            const selected = room.question_seconds === seconds;
            return (
              <button
                key={seconds}
                type="button"
                disabled={!isHost || saving}
                aria-pressed={selected}
                onClick={() => save(() => setQuestionSeconds(token, seconds))}
                className={`rounded-lg border py-2 font-display text-sm font-bold transition duration-200 disabled:cursor-not-allowed disabled:opacity-40 ${
                  selected
                    ? 'border-gold-300 bg-gold-500/15 text-gold-200'
                    : 'border-white/10 bg-white/[0.03] text-ink-300 enabled:hover:border-neon-400/60 enabled:hover:text-white'
                }`}
              >
                {seconds}
              </button>
            );
          })}
        </div>
      </div>

      {!isHost && <p className="text-sm text-ink-400">المضيف فقط يستطيع تغيير إعدادات الغرفة.</p>}

      {error && (
        <p role="alert" className="rounded-xl border border-red-400/40 bg-red-500/10 px-4 py-3 text-sm text-red-200">
          {error}
        </p>
      )}
    </section>
  );
}
