const STEPS = [
  {
    num: "01",
    title: "You open a blank screen.",
    desc: "No dashboard. No sidebar. No onboarding wizard. Just a dark canvas and a prompt bar. The emptiness is the point.",
    icon: (
      <svg width="32" height="32" viewBox="0 0 32 32" fill="none">
        <rect x="4" y="8" width="24" height="16" rx="3" stroke="#6ee7b7" strokeWidth="1.5" />
        <path d="M12 18L16 14L20 18" stroke="#6ee7b7" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
    ),
  },
  {
    num: "02",
    title: "You speak. It builds.",
    desc: "Ask for anything — a tracker, a workflow, a tool. The agent generates the interface on the fly. No code. No config. Just intent.",
    icon: (
      <svg width="32" height="32" viewBox="0 0 32 32" fill="none">
        <rect x="6" y="6" width="8" height="8" rx="2" stroke="#3b82f6" strokeWidth="1.5" />
        <rect x="18" y="6" width="8" height="8" rx="2" stroke="#3b82f6" strokeWidth="1.5" />
        <rect x="6" y="18" width="8" height="8" rx="2" stroke="#3b82f6" strokeWidth="1.5" />
        <rect x="18" y="18" width="8" height="8" rx="2" stroke="#3b82f6" strokeWidth="1.5" />
      </svg>
    ),
  },
  {
    num: "03",
    title: "Everyone feeds the same brain.",
    desc: "Every user has a private session. But the knowledge — memory, skills, decisions — accumulates in one place. The more people use it, the smarter it gets.",
    icon: (
      <svg width="32" height="32" viewBox="0 0 32 32" fill="none">
        <circle cx="16" cy="16" r="10" stroke="#fbbf24" strokeWidth="1.5" />
        <circle cx="16" cy="16" r="3" fill="#fbbf24" />
        <path d="M16 6V10" stroke="#fbbf24" strokeWidth="1.5" strokeLinecap="round" />
        <path d="M16 22V26" stroke="#fbbf24" strokeWidth="1.5" strokeLinecap="round" />
        <path d="M6 16H10" stroke="#fbbf24" strokeWidth="1.5" strokeLinecap="round" />
        <path d="M22 16H26" stroke="#fbbf24" strokeWidth="1.5" strokeLinecap="round" />
      </svg>
    ),
  },
];

export default function HowItWorks() {
  return (
    <section id="how" className="border-t border-[#2a2a2a] px-6 py-24 sm:py-32">
      <div className="mx-auto max-w-5xl">
        <div className="mb-16 text-center">
          <span className="mb-4 inline-block font-mono text-[10px] tracking-[3px] text-[#6b6b6b]">
            HOW IT WORKS
          </span>
          <h2 className="font-sans text-3xl font-bold tracking-tight sm:text-4xl">
            One intelligence. <span className="text-[#6ee7b7]">Many minds.</span>
          </h2>
        </div>

        <div className="grid gap-8 md:grid-cols-3">
          {STEPS.map((step) => (
            <div
              key={step.num}
              className="group rounded-2xl border border-[#2a2a2a] bg-[#141414] p-8 transition hover:border-[#3a3a3a] hover:bg-[#1a1a1a]"
            >
              <div className="mb-6 flex items-center justify-between">
                <div className="flex h-12 w-12 items-center justify-center rounded-xl border border-[#2a2a2a] bg-[#0a0a0a]">
                  {step.icon}
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
              ARCHITECTURE
            </span>
          </div>
          <div className="grid gap-px bg-[#2a2a2a] sm:grid-cols-3">
            {[
              {
                label: "Single OpenClaw Brain",
                detail: "One agent engine — shared memory, skills, and knowledge across all users",
                color: "#6ee7b7",
              },
              {
                label: "Empty Shell",
                detail: "Blank canvas that renders whatever the intelligence produces — nothing more",
                color: "#3b82f6",
              },
              {
                label: "Any Channel In",
                detail: "Web, WhatsApp, Telegram, Discord — all feeding the same brain",
                color: "#fbbf24",
              },
            ].map((item) => (
              <div key={item.label} className="bg-[#0f0f0f] p-6">
                <div className="mb-2 flex items-center gap-2">
                  <span
                    className="h-1.5 w-1.5 rounded-full"
                    style={{ background: item.color }}
                  />
                  <span className="font-mono text-xs tracking-wide" style={{ color: item.color }}>
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
