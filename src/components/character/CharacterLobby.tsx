import { useState } from 'react';
import { AnimatePresence } from 'framer-motion';
import { Loader2, Play } from 'lucide-react';
import { EmptySlot, PlayerCard } from '@/components/room/PlayerCard';
import { InvitePanel } from '@/components/room/InvitePanel';
import { Button } from '@/components/ui/Button';
import {
  startCharacterGame,
  updateCharacterSettings,
  type CharacterCategory,
  type CharacterSettings,
  type CharacterState,
} from '@/lib/characterApi';
import {
  CHARACTER_CATEGORIES,
  CHARACTER_MODES,
  MODE_LABEL,
  QUESTION_OPTIONS,
  ROUND_OPTIONS,
  SECONDS_OPTIONS,
} from '@/lib/characterConstants';
import { getErrorMessage } from '@/lib/roomApi';
import type { Player } from '@/types/room';

interface Props {
  state: CharacterState;
  roomId: string;
  token: string;
  onChanged: () => Promise<void>;
}

const pill = (selected: boolean) =>
  `rounded-lg border py-2 font-display text-sm font-bold transition duration-200 disabled:cursor-not-allowed disabled:opacity-40 ${
    selected
      ? 'border-gold-300 bg-gold-500/15 text-gold-200'
      : 'border-white/10 bg-white/[0.03] text-ink-300 enabled:hover:border-neon-400/60 enabled:hover:text-white'
  }`;

export function CharacterLobby({ state, roomId, token, onChanged }: Props) {
  const isHost = state.me.is_host;
  const { game, players } = state;
  const server: CharacterSettings = {
    mode: game.mode,
    totalRounds: game.total_rounds,
    roundSeconds: game.round_seconds,
    questionsPerPlayer: game.questions_per_player,
    categories: game.categories,
  };
  const [pending, setPending] = useState<CharacterSettings | null>(null);
  const [saving, setSaving] = useState(false);
  const [starting, setStarting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const view = pending ?? server;

  async function save(next: CharacterSettings) {
    setPending(next);
    setSaving(true);
    setError(null);
    try {
      await updateCharacterSettings(token, next);
      await onChanged();
    } catch (err) {
      setError(getErrorMessage(err));
    } finally {
      setPending(null);
      setSaving(false);
    }
  }

  async function start() {
    setStarting(true);
    setError(null);
    try {
      await startCharacterGame(token);
    } catch (err) {
      setError(getErrorMessage(err));
      setStarting(false);
    }
  }

  function toggleCategory(key: CharacterCategory) {
    const has = view.categories.includes(key);
    void save({ ...view, categories: has ? view.categories.filter((c) => c !== key) : [...view.categories, key] });
  }

  const catalog = state.catalog ?? {};
  const available =
    view.categories.length === 0
      ? Object.values(catalog).reduce((a, b) => a + (b ?? 0), 0)
      : view.categories.reduce((a, key) => a + (catalog[key] ?? 0), 0);
  const notEnough = available < view.totalRounds;
  const asPlayers: Player[] = players.map((p) => ({
    id: p.player_id,
    room_id: roomId,
    name: p.name,
    avatar: p.avatar,
    is_host: p.is_host,
    joined_at: p.joined_at,
  }));
  const emptySlots = Math.max(0, state.room.max_players - players.length);

  return (
    <div className="mt-8 grid gap-6 lg:grid-cols-[1fr_380px]">
      <section>
        <div className="flex items-end justify-between gap-4">
          <h1 className="font-display text-2xl font-black tracking-wider text-white sm:text-3xl">اللاعبون</h1>
          <span className="font-display text-lg font-bold text-gold-300">
            {players.length}/{state.room.max_players}
          </span>
        </div>
        <ul className="mt-6 grid grid-cols-2 gap-4 md:grid-cols-3 xl:grid-cols-4">
          <AnimatePresence initial={false}>
            {asPlayers.map((p) => (
              <PlayerCard key={p.id} player={p} isMe={p.id === state.me.player_id} />
            ))}
          </AnimatePresence>
          {Array.from({ length: emptySlots }, (_, i) => (
            <EmptySlot key={`empty-${i}`} />
          ))}
        </ul>

        <div className="mt-8 flex flex-col items-center gap-3">
          {isHost ? (
            <>
              <Button
                variant="gold"
                onClick={start}
                disabled={starting || saving || players.length < 2 || notEnough}
                icon={starting ? <Loader2 className="h-5 w-5 animate-spin" /> : <Play className="h-5 w-5" />}
                className="w-full sm:w-auto"
              >
                ابدأ اللعبة
              </Button>
              {players.length < 2 && <p className="text-sm text-ink-400">تحتاج إلى لاعبين اثنين على الأقل.</p>}
              {notEnough && (
                <p className="text-sm text-amber-300">
                  المتاح {available} شخصية فقط في هذه التصنيفات، وعدد الجولات {view.totalRounds}.
                </p>
              )}
            </>
          ) : (
            <p className="text-center text-sm text-ink-400">بانتظار المضيف لبدء اللعبة.</p>
          )}
          {error && (
            <p role="alert" className="rounded-xl border border-red-400/40 bg-red-500/10 px-4 py-3 text-sm text-red-200">
              {error}
            </p>
          )}
        </div>
      </section>

      <aside className="flex flex-col gap-6">
        <InvitePanel code={state.room.code} />
        <section className="glass flex flex-col gap-5 p-6">
          <header className="flex items-center justify-between gap-3">
            <h2 className="font-display text-sm font-bold tracking-[0.2em] text-white">إعدادات خمن الشخصية</h2>
            {saving && <Loader2 className="h-4 w-4 animate-spin text-neon-300" />}
          </header>

          <div>
            <span className="label">وضع اللعب</span>
            <div className="grid gap-2">
              {CHARACTER_MODES.map(({ key, title, text, Icon, defaults }) => {
                const selected = view.mode === key;
                return (
                  <button
                    key={key}
                    type="button"
                    disabled={!isHost || saving}
                    aria-pressed={selected}
                    onClick={() =>
                      void save({ ...view, mode: key, roundSeconds: defaults.roundSeconds, questionsPerPlayer: defaults.questionsPerPlayer })
                    }
                    className={`flex items-start gap-3 rounded-xl border p-3 text-start transition duration-200 disabled:cursor-not-allowed ${
                      selected ? 'border-neon-400 bg-neon-500/15 shadow-neon' : 'border-white/10 bg-white/[0.03] enabled:hover:border-neon-400/50'
                    }`}
                  >
                    <Icon className="mt-0.5 h-5 w-5 shrink-0 text-neon-300" />
                    <span>
                      <span className="block font-display text-sm font-bold text-white">{title}</span>
                      <span className="mt-1 block text-xs leading-[1.6] text-ink-300">{text}</span>
                    </span>
                  </button>
                );
              })}
            </div>
          </div>

          <div>
            <span className="label">عدد الجولات</span>
            <div className="grid grid-cols-4 gap-2">
              {ROUND_OPTIONS.map((n) => (
                <button key={n} type="button" disabled={!isHost || saving} aria-pressed={view.totalRounds === n} onClick={() => void save({ ...view, totalRounds: n })} className={pill(view.totalRounds === n)}>
                  {n}
                </button>
              ))}
            </div>
          </div>

          <div>
            <span className="label">وقت الجولة (ثانية)</span>
            <div className="grid grid-cols-5 gap-2">
              {SECONDS_OPTIONS.map((n) => (
                <button key={n} type="button" disabled={!isHost || saving} aria-pressed={view.roundSeconds === n} onClick={() => void save({ ...view, roundSeconds: n })} className={pill(view.roundSeconds === n)}>
                  {n}
                </button>
              ))}
            </div>
          </div>

          <div>
            <span className="label">أسئلة نعم/لا لكل لاعب في الجولة</span>
            <div className="grid grid-cols-6 gap-2">
              {QUESTION_OPTIONS.map((n) => (
                <button key={n} type="button" disabled={!isHost || saving} aria-pressed={view.questionsPerPlayer === n} onClick={() => void save({ ...view, questionsPerPlayer: n })} className={pill(view.questionsPerPlayer === n)}>
                  {n}
                </button>
              ))}
            </div>
          </div>

          <div>
            <span className="label">التصنيفات {view.categories.length === 0 && <span className="text-ink-400">(الكل)</span>}</span>
            <div className="flex flex-wrap gap-2">
              {CHARACTER_CATEGORIES.map(({ key, label }) => {
                const selected = view.categories.includes(key);
                return (
                  <button
                    key={key}
                    type="button"
                    disabled={!isHost || saving}
                    aria-pressed={selected}
                    onClick={() => toggleCategory(key)}
                    className={`rounded-full border px-3 py-1.5 text-xs font-bold transition disabled:cursor-not-allowed ${
                      selected ? 'border-gold-300 bg-gold-500/15 text-gold-200' : 'border-white/10 bg-white/[0.03] text-ink-300 enabled:hover:border-neon-400/60'
                    }`}
                  >
                    {label} <span className="text-ink-400">({catalog[key] ?? 0})</span>
                  </button>
                );
              })}
            </div>
          </div>

          {!isHost && (
            <p className="text-xs text-ink-400">
              الوضع الحالي: <b className="text-white">{MODE_LABEL[view.mode]}</b>. المضيف فقط يستطيع تغيير الإعدادات.
            </p>
          )}
        </section>
      </aside>
    </div>
  );
}
