import { useState, type FormEvent } from 'react';
import { Dices, Loader2, ScanFace, Swords, Users } from 'lucide-react';
import { AvatarPicker } from '@/components/room/AvatarPicker';
import { FormShell } from '@/components/room/FormShell';
import { Button } from '@/components/ui/Button';
import { createCharacterRoom, createRoom, getErrorMessage, type CreatedRoomSession } from '@/lib/roomApi';
import type { AvatarKey, GameMode } from '@/types/room';

const PLAYER_OPTIONS = [2, 3, 4, 5, 6, 7, 8];

type GameChoice = 'risk_it' | 'guess_character';

const GAME_OPTIONS: { value: GameChoice; title: string; text: string; Icon: typeof Users }[] = [
  { value: 'risk_it', title: 'RISK IT', text: 'أسئلة ورهانات وسرقة نقاط بين الأصدقاء.', Icon: Dices },
  { value: 'guess_character', title: 'خمن الشخصية', text: 'تلميحات وأسئلة نعم/لا لاكتشاف الشخصية المشهورة قبل الجميع.', Icon: ScanFace },
];

const MODE_OPTIONS: { value: GameMode; title: string; text: string; Icon: typeof Users }[] = [
  { value: 'solo', title: 'SOLO', text: 'كل لاعب يلعب لنفسه ويجمع أكبر عدد من النقاط.', Icon: Users },
  { value: 'team', title: 'TEAM', text: 'فريقان: Team Purple وTeam Gold برصيد مشترك.', Icon: Swords },
];

interface CreateRoomFormProps {
  variant: 'create' | 'friends';
  onCreated: (session: CreatedRoomSession) => void;
  onBack: () => void;
}

export function CreateRoomForm({ variant, onCreated, onBack }: CreateRoomFormProps) {
  const [name, setName] = useState('');
  const [avatar, setAvatar] = useState<AvatarKey>('crown');
  const [maxPlayers, setMaxPlayers] = useState(4);
  const [gameMode, setGameMode] = useState<GameMode>('solo');
  const [game, setGame] = useState<GameChoice>('risk_it');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const isFriends = variant === 'friends';

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const trimmed = name.trim();
    if (!trimmed) {
      setError('اكتب اسمك أولًا.');
      return;
    }

    setSubmitting(true);
    setError(null);
    try {
      const session =
        game === 'guess_character'
          ? await createCharacterRoom({ name: trimmed, avatar, maxPlayers })
          : await createRoom({ name: trimmed, avatar, maxPlayers, gameMode });
      onCreated(session);
    } catch (err) {
      setError(getErrorMessage(err));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <FormShell
      title={isFriends ? 'PLAY WITH FRIENDS' : 'CREATE ROOM'}
      subtitle={
        isFriends
          ? 'أنشئ الغرفة في ثوانٍ، ثم شارك الكود أو الرابط مع أصحابك.'
          : 'اختر اسمك وصورتك وإعدادات الغرفة، وستصبح أنت المضيف.'
      }
      onBack={onBack}
    >
      <form onSubmit={handleSubmit} className="flex flex-col gap-8" noValidate>
        <div>
          <span className="label">اللعبة</span>
          <div className="grid gap-3 sm:grid-cols-2">
            {GAME_OPTIONS.map(({ value, title, text, Icon }) => {
              const selected = game === value;
              return (
                <button
                  key={value}
                  type="button"
                  aria-pressed={selected}
                  onClick={() => setGame(value)}
                  className={`flex flex-col gap-2 rounded-2xl border p-4 text-start transition duration-200 ${
                    selected ? 'border-gold-300 bg-gold-500/10 shadow-gold' : 'border-white/10 bg-white/[0.03] hover:border-neon-400/50'
                  }`}
                >
                  <span className="flex items-center gap-2 font-display font-bold tracking-wide text-white">
                    <Icon className="h-4 w-4 text-gold-300" />
                    {title}
                  </span>
                  <span className="text-sm leading-[1.5] text-ink-300">{text}</span>
                </button>
              );
            })}
          </div>
        </div>

        <div>
          <label htmlFor="create-name" className="label">
            اسمك في اللعبة
          </label>
          <input
            id="create-name"
            className="field"
            value={name}
            maxLength={16}
            placeholder="مثال: أحمد"
            autoComplete="nickname"
            onChange={(event) => setName(event.target.value)}
          />
        </div>

        <div>
          <span className="label">صورتك الرمزية</span>
          <AvatarPicker value={avatar} onChange={setAvatar} />
        </div>

        <div>
          <span className="label">عدد اللاعبين</span>
          <div className="grid grid-cols-7 gap-2">
            {PLAYER_OPTIONS.map((count) => (
              <button
                key={count}
                type="button"
                aria-pressed={maxPlayers === count}
                onClick={() => setMaxPlayers(count)}
                className={`rounded-xl border py-3 font-display text-lg font-bold transition duration-200 ${
                  maxPlayers === count
                    ? 'border-gold-300 bg-gold-500/15 text-gold-200 shadow-gold'
                    : 'border-white/10 bg-white/[0.03] text-ink-300 hover:border-neon-400/60 hover:text-white'
                }`}
              >
                {count}
              </button>
            ))}
          </div>
        </div>

        {game === 'risk_it' && (
        <div>
          <span className="label">نظام اللعب</span>
          <div className="grid gap-3 sm:grid-cols-2">
            {MODE_OPTIONS.map(({ value, title, text, Icon }) => {
              const selected = gameMode === value;
              return (
                <button
                  key={value}
                  type="button"
                  aria-pressed={selected}
                  onClick={() => setGameMode(value)}
                  className={`flex flex-col gap-2 rounded-2xl border p-4 text-start transition duration-200 ${
                    selected
                      ? 'border-neon-400 bg-neon-500/15 shadow-neon'
                      : 'border-white/10 bg-white/[0.03] hover:border-neon-400/50'
                  }`}
                >
                  <span className="flex items-center gap-2 font-display font-bold tracking-wide text-white">
                    <Icon className="h-4 w-4 text-neon-300" />
                    {title}
                  </span>
                  <span className="text-sm leading-[1.5] text-ink-300">{text}</span>
                </button>
              );
            })}
          </div>
        </div>
        )}

        {error && (
          <p role="alert" className="rounded-xl border border-red-400/40 bg-red-500/10 px-4 py-3 text-sm text-red-200">
            {error}
          </p>
        )}

        <Button type="submit" variant="primary" disabled={submitting} className="w-full py-4 text-lg">
          {submitting && <Loader2 className="h-5 w-5 animate-spin" />}
          {submitting ? 'جاري إنشاء الغرفة...' : 'أنشئ الغرفة'}
        </Button>
      </form>
    </FormShell>
  );
}
