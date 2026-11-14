import { useState } from 'react';
import { Check, Copy, Link2 } from 'lucide-react';

interface InvitePanelProps {
  code: string;
}

export function InvitePanel({ code }: InvitePanelProps) {
  const [copied, setCopied] = useState<'code' | 'link' | null>(null);
  const [copyError, setCopyError] = useState(false);

  const inviteLink = `${window.location.origin}${window.location.pathname}?room=${code}`;

  async function copy(value: string, kind: 'code' | 'link') {
    try {
      await navigator.clipboard.writeText(value);
      setCopied(kind);
      setCopyError(false);
      window.setTimeout(() => setCopied(null), 2000);
    } catch {
      setCopyError(true);
    }
  }

  return (
    <section className="glass p-6">
      <p className="text-xs font-bold uppercase tracking-[0.3em] text-gold-300">Room Code</p>
      <div className="mt-3 flex items-center justify-between gap-3">
        <span className="font-display text-3xl font-black tracking-[0.25em] text-white sm:text-4xl">{code}</span>
        <button
          type="button"
          onClick={() => copy(code, 'code')}
          className="inline-flex items-center gap-2 rounded-xl border border-white/15 bg-white/[0.04] px-3 py-2 text-sm transition hover:border-gold-300/60 hover:text-gold-200"
        >
          {copied === 'code' ? <Check className="h-4 w-4 text-emerald-300" /> : <Copy className="h-4 w-4" />}
          {copied === 'code' ? 'تم النسخ' : 'نسخ الكود'}
        </button>
      </div>

      <button
        type="button"
        onClick={() => copy(inviteLink, 'link')}
        className="mt-5 flex w-full items-center gap-3 rounded-xl border border-dashed border-white/15 bg-ink-900/60 px-4 py-3 text-start text-sm text-ink-300 transition hover:border-neon-400/60 hover:text-white"
      >
        <Link2 className="h-4 w-4 shrink-0 text-neon-300" />
        <span className="flex-1 truncate">{inviteLink}</span>
        <span className="shrink-0 font-bold text-neon-300">{copied === 'link' ? 'تم النسخ' : 'نسخ الرابط'}</span>
      </button>

      {copyError && <p className="mt-3 text-sm text-amber-300">تعذر النسخ تلقائيًا، انسخ الكود يدويًا.</p>}
    </section>
  );
}
