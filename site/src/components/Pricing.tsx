const TIERS = [
  {
    name: "Spark",
    price: "Free",
    period: "forever",
    desc: "Self-hosted. One brain, your keys.",
    features: [
      "500 agent turns / month",
      "1 channel (web shell)",
      "Shared memory across users",
      "Community support",
    ],
    cta: "Start Free",
    ctaStyle: "border border-[#2a2a2a] bg-[#141414] text-[#e5e5e5] hover:bg-[#1a1a1a]",
    highlight: false,
  },
  {
    name: "Flow",
    price: "$19",
    period: "/ month",
    desc: "For teams feeding one intelligence daily.",
    features: [
      "5,000 agent turns / month",
      "3 channels (web + messaging)",
      "Collective memory & skills",
      "Cron jobs & workflows",
      "Email support",
    ],
    cta: "Start with Flow",
    ctaStyle: "bg-[#6ee7b7] text-[#0a0a0a] hover:bg-[#5dd4a6]",
    highlight: true,
  },
  {
    name: "Autonomy",
    price: "$49",
    period: "/ month",
    desc: "The brain runs unsupervised.",
    features: [
      "25,000 agent turns / month",
      "Unlimited channels",
      "Elevated mode & browser tool",
      "Priority model access",
      "Priority support",
    ],
    cta: "Go Autonomous",
    ctaStyle: "border border-[#3b82f6] bg-[#3b82f6]/10 text-[#3b82f6] hover:bg-[#3b82f6]/20",
    highlight: false,
  },
  {
    name: "Unlimited",
    price: "$99",
    period: "/ month",
    desc: "No limits. The brain never stops learning.",
    features: [
      "Unlimited agent turns",
      "Unlimited channels & users",
      "Dedicated sandbox",
      "Custom agent identity",
      "API access & webhooks",
      "Dedicated support",
    ],
    cta: "Contact Us",
    ctaStyle: "border border-[#2a2a2a] bg-[#141414] text-[#e5e5e5] hover:bg-[#1a1a1a]",
    highlight: false,
  },
];

export default function Pricing() {
  return (
    <section id="pricing" className="border-t border-[#2a2a2a] px-6 py-24 sm:py-32">
      <div className="mx-auto max-w-6xl">
        <div className="mb-16 text-center">
          <span className="mb-4 inline-block font-mono text-[10px] tracking-[3px] text-[#6b6b6b]">
            PRICING
          </span>
          <h2 className="font-sans text-3xl font-bold tracking-tight sm:text-4xl">
            Pay for <span className="text-[#6ee7b7]">capacity</span>, not features.
          </h2>
          <p className="mx-auto mt-4 max-w-xl font-sans text-sm text-[#6b6b6b]">
            There are no features to tier. You pay for how many turns
            your collective intelligence gets — and how far you let it go alone.
          </p>
        </div>

        <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-4">
          {TIERS.map((tier) => (
            <div
              key={tier.name}
              className={`relative flex flex-col rounded-2xl border p-6 transition ${
                tier.highlight
                  ? "border-[#6ee7b7]/40 bg-[#0a1a10]"
                  : "border-[#2a2a2a] bg-[#141414] hover:border-[#3a3a3a]"
              }`}
            >
              {tier.highlight && (
                <span className="absolute -top-3 left-1/2 -translate-x-1/2 rounded-full bg-[#6ee7b7] px-3 py-0.5 font-mono text-[9px] font-bold tracking-widest text-[#0a0a0a]">
                  POPULAR
                </span>
              )}

              <div className="mb-4">
                <h3 className="font-mono text-xs tracking-[2px] text-[#6b6b6b]">
                  {tier.name.toUpperCase()}
                </h3>
              </div>

              <div className="mb-2 flex items-baseline gap-1">
                <span className="font-sans text-3xl font-bold">{tier.price}</span>
                {tier.period !== "forever" && (
                  <span className="font-sans text-sm text-[#6b6b6b]">
                    {tier.period}
                  </span>
                )}
              </div>

              <p className="mb-6 font-sans text-xs text-[#6b6b6b]">{tier.desc}</p>

              <ul className="mb-8 flex-1 space-y-3">
                {tier.features.map((f) => (
                  <li key={f} className="flex items-start gap-2 text-sm">
                    <svg
                      width="16"
                      height="16"
                      viewBox="0 0 16 16"
                      fill="none"
                      className="mt-0.5 shrink-0"
                    >
                      <path
                        d="M4 8L7 11L12 5"
                        stroke={tier.highlight ? "#6ee7b7" : "#3a3a3a"}
                        strokeWidth="1.5"
                        strokeLinecap="round"
                        strokeLinejoin="round"
                      />
                    </svg>
                    <span className="font-sans text-[#8b8b8b]">{f}</span>
                  </li>
                ))}
              </ul>

              <a
                href="#"
                className={`block rounded-xl py-2.5 text-center font-mono text-xs tracking-wide transition ${tier.ctaStyle}`}
              >
                {tier.cta}
              </a>
            </div>
          ))}
        </div>

        <p className="mt-8 text-center font-mono text-[10px] tracking-wide text-[#3a3a3a]">
          All tiers: one brain per instance, open-source shell, self-host option, $0.01/turn overage
        </p>
      </div>
    </section>
  );
}
