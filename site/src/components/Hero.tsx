"use client";

import TerminalDemo from "./TerminalDemo";

export default function Hero() {
  return (
    <section className="relative flex min-h-screen flex-col items-center justify-center overflow-hidden px-6">
      <div
        className="pointer-events-none absolute inset-0 opacity-[0.03]"
        style={{
          backgroundImage:
            "linear-gradient(#6ee7b7 1px, transparent 1px), linear-gradient(90deg, #6ee7b7 1px, transparent 1px)",
          backgroundSize: "60px 60px",
        }}
      />

      <div className="pointer-events-none absolute top-1/3 left-1/2 h-[500px] w-[500px] -translate-x-1/2 -translate-y-1/2 rounded-full bg-[#6ee7b7]/5 blur-[120px]" />

      <div className="relative z-10 mx-auto max-w-3xl text-center">
        <h1 className="animate-fade-up font-sans text-4xl font-bold leading-tight tracking-tight sm:text-5xl md:text-6xl lg:text-7xl">
          Nothing ships.
          <br />
          <span className="text-[#6ee7b7]">Everything emerges.</span>
        </h1>

        <p className="animate-fade-up-delay-1 mx-auto mt-6 max-w-xl font-sans text-base leading-relaxed text-[#8b8b8b] sm:text-lg">
          An empty screen. A single intelligence. Every person who connects
          teaches it something new. The app doesn&apos;t exist until you speak.
        </p>

        <div className="animate-fade-up-delay-2 mt-10">
          <a
            href="#"
            className="rounded-xl bg-[#6ee7b7] px-8 py-3 font-mono text-sm font-bold tracking-wide text-[#0a0a0a] transition hover:bg-[#5dd4a6]"
          >
            JOIN THE BRAIN
          </a>
        </div>
      </div>

      <div className="relative z-10 mx-auto mt-20 w-full max-w-2xl animate-fade-up-delay-3">
        <TerminalDemo />
      </div>

      <p className="relative z-10 mt-12 animate-fade-up-delay-3 font-mono text-[10px] tracking-[3px] text-[#2a2a2a]">
        PRIVATE CONVERSATIONS. COLLECTIVE WISDOM.
      </p>
    </section>
  );
}
