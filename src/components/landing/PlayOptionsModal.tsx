import { DoorOpen, Plus, Users } from 'lucide-react';
import { Modal } from '@/components/ui/Modal';

interface PlayOptionsModalProps {
  open: boolean;
  onClose: () => void;
  onCreate: () => void;
  onJoin: () => void;
  onFriends: () => void;
}

const OPTIONS = [
  { key: 'create', title: 'Create Room', subtitle: 'أنشئ غرفة جديدة وكن المضيف', Icon: Plus },
  { key: 'join', title: 'Join Room', subtitle: 'ادخل غرفة باستخدام الكود', Icon: DoorOpen },
  { key: 'friends', title: 'Play With Friends', subtitle: 'اختصر الطريق وشارك الكود مع أصحابك', Icon: Users },
] as const;

export function PlayOptionsModal({ open, onClose, onCreate, onJoin, onFriends }: PlayOptionsModalProps) {
  const handlers = { create: onCreate, join: onJoin, friends: onFriends };

  return (
    <Modal open={open} title="PLAY NOW" onClose={onClose}>
      <div className="flex flex-col gap-3">
        {OPTIONS.map(({ key, title, subtitle, Icon }) => (
          <button
            key={key}
            type="button"
            onClick={handlers[key]}
            className="group flex items-center gap-4 rounded-2xl border border-white/10 bg-white/[0.03] p-4 text-start transition duration-300 hover:-translate-y-0.5 hover:border-neon-400/60 hover:bg-neon-500/10 hover:shadow-neon"
          >
            <span className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-gradient-to-br from-neon-500 to-electric-500 text-white transition group-hover:scale-105">
              <Icon className="h-6 w-6" />
            </span>
            <span className="flex flex-col">
              <span className="font-display text-base font-bold tracking-wide text-white">{title}</span>
              <span className="mt-1 text-sm text-ink-300">{subtitle}</span>
            </span>
          </button>
        ))}
      </div>
    </Modal>
  );
}
