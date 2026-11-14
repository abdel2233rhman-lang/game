export function HeroBackground() {
  return (
    <div aria-hidden="true" className="pointer-events-none fixed inset-0 overflow-hidden">
      <div className="absolute inset-0 bg-[linear-gradient(rgba(168,85,247,0.07)_1px,transparent_1px),linear-gradient(90deg,rgba(168,85,247,0.07)_1px,transparent_1px)] bg-[size:56px_56px] [mask-image:radial-gradient(ellipse_at_center,black_40%,transparent_80%)]" />
      <div className="absolute -left-32 -top-32 h-[28rem] w-[28rem] animate-float rounded-full bg-neon-600/30 blur-[120px]" />
      <div className="absolute -bottom-40 -right-24 h-[32rem] w-[32rem] animate-float-slow rounded-full bg-gold-500/20 blur-[140px]" />
      <div className="absolute left-1/2 top-1/3 h-72 w-72 -translate-x-1/2 animate-glow-pulse rounded-full bg-electric-500/20 blur-[100px]" />
    </div>
  );
}
