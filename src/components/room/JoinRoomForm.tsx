import { useState, type FormEvent } from 'react';
import { Loader2 } from 'lucide-react';
import { AvatarPicker } from '@/components/room/AvatarPicker';
import { FormShell } from '@/components/room/FormShell';
import { Button } from '@/components/ui/Button';
import { getErrorMessage, joinRoom, type CreatedRoomSession } from '@/lib/roomApi';
import type { AvatarKey } from '@/types/room';

const CODE_LENGTH = 6;

interface JoinRoomFormProps {
  initialCode: string;
  onJoined: (session: CreatedRoomSession) => void;
  onBack: () => void;
}

export function JoinRoomForm({ initialCode, onJoined, onBack }: JoinRoomFormProps) {
  const [code, setCode] = useState(initialCode.toUpperCase().slice(0, CODE_LENGTH));
  const [name, setName] = useState('');
  const [avatar, setAvatar] = useState<AvatarKey>('rocket');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const trimmedName = name.trim();
    if (code.length !== CODE_LENGTH) {
      setError('كود الغرفة مكون من 6 حروف أو أرقام.');
      return;
    }
    if (!trimmedName) {
      setError('اكتب اسمك أولًا.');
      return;
    }

    setSubmitting(true);
    setError(null);
    try {
      const session = await joinRoom({ code, name: trimmedName, avatar });
      onJoined(session);
    } catch (err) {
      setError(getErrorMessage(err));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <FormShell
      title="JOIN ROOM"
      subtitle="اكتب كود الغرفة الذي أرسله لك المضيف، واختر اسمك وصورتك."
      onBack={onBack}
    >
      <form onSubmit={handleSubmit} className="flex flex-col gap-8" noValidate>
        <div>
          <label htmlFor="join-code" className="label">
            كود الغرفة
          </label>
          <input
            id="join-code"
            className="field text-center font-display text-2xl font-bold uppercase tracking-[0.4em] sm:text-3xl"
            value={code}
            maxLength={CODE_LENGTH}
            inputMode="text"
            autoCapitalize="characters"
            autoComplete="off"
            spellCheck={false}
            placeholder="ABC123"
            onChange={(event) => setCode(event.target.value.toUpperCase().replace(/[^A-Z0-9]/g, ''))}
          />
        </div>

        <div>
          <label htmlFor="join-name" className="label">
            اسمك في اللعبة
          </label>
          <input
            id="join-name"
            className="field"
            value={name}
            maxLength={16}
            placeholder="مثال: سارة"
            autoComplete="nickname"
            onChange={(event) => setName(event.target.value)}
          />
        </div>

        <div>
          <span className="label">صورتك الرمزية</span>
          <AvatarPicker value={avatar} onChange={setAvatar} />
        </div>

        {error && (
          <p role="alert" className="rounded-xl border border-red-400/40 bg-red-500/10 px-4 py-3 text-sm text-red-200">
            {error}
          </p>
        )}

        <Button type="submit" variant="primary" disabled={submitting} className="w-full py-4 text-lg">
          {submitting && <Loader2 className="h-5 w-5 animate-spin" />}
          {submitting ? 'جاري الدخول...' : 'ادخل الغرفة'}
        </Button>
      </form>
    </FormShell>
  );
}
