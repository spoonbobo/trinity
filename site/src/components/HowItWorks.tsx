"use client";

import { useI18n } from "@/i18n/context";

const ICONS = [
  <svg key="0" width="32" height="32" viewBox="0 0 32 32" fill="none">
    <rect x="4" y="8" width="24" height="16" rx="3" stroke="#6ee7b7" strokeWidth="1.5" />
    <path d="M12 18L16 14L20 18" stroke="#6ee7b7" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
  </svg>,
  <svg key="1" width="32" height="32" viewBox="0 0 32 32" fill="none">
    <rect x="6" y="6" width="8" height="8" rx="2" stroke="#3b82f6" strokeWidth="1.5" />
    <rect x="18" y="6" width="8" height="8" rx="2" stroke="#3b82f6" strokeWidth="1.5" />
    <rect x="6" y="18" width="8" height="8" rx="2" stroke="#3b82f6" strokeWidth="1.5" />
    <rect x="18" y="18" width="8" height="8" rx="2" stroke="#3b82f6" strokeWidth="1.5" />
  </svg>,
  <svg key="2" width="32" height="32" viewBox="0 0 32 32" fill="none">
    <circle cx="16" cy="16" r="10" stroke="#fbbf24" strokeWidth="1.5" />
    <circle cx="16" cy="16" r="3" fill="#fbbf24" />
    <path d="M16 6V10" stroke="#fbbf24" strokeWidth="1.5" strokeLinecap="round" />
    <path d="M16 22V26" stroke="#fbbf24" strokeWidth="1.5" strokeLinecap="round" />
    <path d="M6 16H10" stroke="#fbbf24" strokeWidth="1.5" strokeLinecap="round" />
    <path d="M22 16H26" stroke="#fbbf24" strokeWidth="1.5" strokeLinecap="round" />
  </svg>,
];

const ARCH_COLORS = ["#6ee7b7", "#3b82f6", "#fbbf24"];

export default function HowItWorks() {
  const { t } = useI18n();

  return (
    <section id="how" className="border-t border-[#2a2a2a] px-6 py-24 sm:py-32">
      <div className="mx-auto max-w-5xl">
        <div className="mb-16 text-center">
          <span className="mb-4 inline-block font-mono text-[10px] tracking-[3px] text-[#6b6b6b]">
            {t.how.label}
          </span>
          <h2 className="font-sans text-3xl font-bold tracking-tight sm:text-4xl">
            {t.how.h2a} <span className="text-[#6ee7b7]">{t.how.h2b}</span>
          </h2>
        </div>

        <div className="grid gap-8 md:grid-cols-3">
          {t.how.steps.map((step, i) => (
            <div
              key={i}
              className="group rounded-2xl border border-[#2a2a2a] bg-[#141414] p-8 transition hover:border-[#3a3a3a] hover:bg-[#1a1a1a]"
            >
              <div className="mb-6 flex items-center justify-between">
                <div className="flex h-12 w-12 items-center justify-center rounded-xl border border-[#2a2a2a] bg-[#0a0a0a]">
                  {ICONS[i]}
                </div>
                <span className="font-mono text-2xl font-bold text-[#2a2a2a] transition group-hover:text-[#3a3a3a]">
                  {step.num}
                </span>
              </div>
              <h3 className="mb-3 font-sans text-lg font-semibold">
                {step.title}
              </h3>
              <p className="font-sans text-sm leading-relaxed text-[#6b6b6b]">
                {step.desc}
              </p>
            </div>
          ))}
        </div>

        <div className="mt-16 overflow-hidden rounded-2xl border border-[#2a2a2a] bg-[#0f0f0f]">
          <div className="border-b border-[#2a2a2a] px-6 py-3">
            <span className="font-mono text-[10px] tracking-[3px] text-[#3a3a3a]">
              {t.how.archLabel}
            </span>
          </div>
          <div className="grid gap-px bg-[#2a2a2a] sm:grid-cols-3">
            {t.how.arch.map((item, i) => (
              <div key={i} className="bg-[#0f0f0f] p-6">
                <div className="mb-2 flex items-center gap-2">
                  <span
                    className="h-1.5 w-1.5 rounded-full"
                    style={{ background: ARCH_COLORS[i] }}
                  />
                  <span className="font-mono text-xs tracking-wide" style={{ color: ARCH_COLORS[i] }}>
                    {item.label}
                  </span>
                </div>
                <p className="font-sans text-xs text-[#6b6b6b]">{item.detail}</p>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
