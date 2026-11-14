import { Trophy } from 'lucide-react';
import { Modal } from '@/components/ui/Modal';

interface LeaderboardModalProps {
  open: boolean;
  onClose: () => void;
}

export function LeaderboardModal({ open, onClose }: LeaderboardModalProps) {
  return (
    <Modal open={open} title="LEADERBOARD" onClose={onClose}>
      <div className="flex flex-col items-center gap-4 py-6 text-center">
        <span className="flex h-16 w-16 items-center justify-center rounded-2xl border border-gold-400/40 bg-gold-500/10">
          <Trophy className="h-8 w-8 text-gold-300" />
        </span>
        <h3 className="text-lg font-bold text-white">لا توجد نتائج بعد</h3>
        <p className="max-w-sm text-sm leading-[1.5] text-ink-300">
          ستظهر هنا ترتيب اللاعبين وإحصائياتهم بعد انتهاء أول مباراة مكتملة.
        </p>
      </div>
    </Modal>
  );
}
