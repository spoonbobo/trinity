"use client";

import { useEffect, useState } from "react";

const LINES = [
  { type: "user", text: "> Show me what the team logged yesterday" },
  { type: "agent", text: "Searching shared memory..." },
  { type: "tool", text: "[memory] 3 entries from 2 contributors" },
  { type: "agent", text: "Rod deployed the API. Mia filed the compliance doc. Alex fixed the auth bug." },
  { type: "gap", text: "" },
  { type: "user", text: "> Build me a project tracker based on that" },
  { type: "agent", text: "Generating tracker from collective context..." },
  { type: "tool", text: "[canvas] Rendering UI surface" },
  { type: "agent", text: "Done. Live on your canvas — pre-filled with what everyone contributed." },
  { type: "gap", text: "" },
  { type: "user", text: "> Remember: deployments need sign-off from Rod" },
  { type: "agent", text: "Written to shared memory. All users will know." },
];

export default function TerminalDemo() {
  const [visibleLines, setVisibleLines] = useState(0);

  useEffect(() => {
    const timer = setInterval(() => {
      setVisibleLines((prev) => {
        if (prev >= LINES.length) {
          clearInterval(timer);
          return prev;
        }
        return prev + 1;
      });
    }, 600);
    return () => clearInterval(timer);
  }, []);

  return (
    <div className="overflow-hidden rounded-xl border border-[#2a2a2a] bg-[#0f0f0f] shadow-2xl shadow-black/50">
      <div className="flex items-center gap-2 border-b border-[#2a2a2a] px-4 py-2.5">
        <span className="h-3 w-3 rounded-full bg-[#ef4444]/60" />
        <span className="h-3 w-3 rounded-full bg-[#fbbf24]/60" />
        <span className="h-3 w-3 rounded-full bg-[#6ee7b7]/60" />
        <span className="ml-3 font-mono text-[10px] tracking-widest text-[#3a3a3a]">
          TRINITY AGI
        </span>
      </div>

      <div className="p-4 font-mono text-xs leading-6 sm:p-6 sm:text-sm sm:leading-7">
        {LINES.slice(0, visibleLines).map((line, i) => {
          if (line.type === "gap") return <div key={i} className="h-3" />;

          if (line.type === "user")
            return (
              <div key={i} className="text-[#e5e5e5]">
                {line.text}
                {i === visibleLines - 1 && <span className="cursor-blink" />}
              </div>
            );

          if (line.type === "agent")
            return (
              <div key={i} className="text-[#8b8b8b]">
                {line.text}
              </div>
            );

          if (line.type === "tool")
            return (
              <div key={i} className="text-[#3b82f6]">
                {line.text}
              </div>
            );

          return null;
        })}
        {visibleLines < LINES.length && (
          <span className="cursor-blink inline-block text-[#6ee7b7]" />
        )}
      </div>
    </div>
  );
}
