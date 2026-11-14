import { Loader2, Wifi, WifiOff } from 'lucide-react';
import type { ConnectionState } from '@/hooks/useRoomSync';

export function ConnectionBadge({ state }: { state: ConnectionState }) {
  if (state === 'live') {
    return (
      <span className="inline-flex items-center gap-2 rounded-full border border-emerald-400/40 bg-emerald-500/10 px-3 py-1.5 text-xs font-bold text-emerald-200">
        <Wifi className="h-3.5 w-3.5" />
        متصل مباشرة
      </span>
    );
  }
  if (state === 'offline') {
    return (
      <span className="inline-flex items-center gap-2 rounded-full border border-amber-400/40 bg-amber-500/10 px-3 py-1.5 text-xs font-bold text-amber-200">
        <WifiOff className="h-3.5 w-3.5" />
        انقطع الاتصال، جاري إعادة الاتصال
      </span>
    );
  }
  return (
    <span className="inline-flex items-center gap-2 rounded-full border border-white/15 bg-white/5 px-3 py-1.5 text-xs font-bold text-ink-200">
      <Loader2 className="h-3.5 w-3.5 animate-spin" />
      جاري الاتصال
    </span>
  );
}
