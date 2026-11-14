import type { ReactNode } from 'react';
import { ArrowRight } from 'lucide-react';

interface FormShellProps {
  title: string;
  subtitle: string;
  onBack: () => void;
  children: ReactNode;
}

export function FormShell({ title, subtitle, onBack, children }: FormShellProps) {
  return (
    <main className="relative z-10 mx-auto flex min-h-screen w-full max-w-2xl flex-col justify-center px-4 py-12 sm:px-6">
      <button
        type="button"
        onClick={onBack}
        className="mb-6 inline-flex w-fit items-center gap-2 rounded-xl px-3 py-2 text-sm text-ink-300 transition hover:bg-white/5 hover:text-white"
      >
        <ArrowRight className="h-4 w-4" />
        رجوع
      </button>

      <div className="glass p-6 shadow-neon sm:p-10">
        <h1 className="font-display text-2xl font-black tracking-wider gold-text sm:text-3xl">{title}</h1>
        <p className="mt-2 text-sm leading-[1.5] text-ink-300 sm:text-base">{subtitle}</p>
        <div className="mt-8 flex flex-col gap-8">{children}</div>
      </div>
    </main>
  );
}
