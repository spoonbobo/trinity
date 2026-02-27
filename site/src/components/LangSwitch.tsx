"use client";

import { useState, useRef, useEffect } from "react";
import { useI18n } from "@/i18n/context";
import { locales, localeLabels } from "@/i18n/translations";

export default function LangSwitch() {
  const { locale, setLocale } = useI18n();
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function handleClick(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener("mousedown", handleClick);
    return () => document.removeEventListener("mousedown", handleClick);
  }, []);

  return (
    <div ref={ref} className="fixed bottom-6 right-6 z-50">
      {open && (
        <div className="mb-2 flex flex-col overflow-hidden rounded-lg border border-[#2a2a2a] bg-[#141414] shadow-xl shadow-black/40">
          {locales.filter((l) => l !== locale).map((l) => (
            <button
              key={l}
              onClick={() => { setLocale(l); setOpen(false); }}
              className="px-4 py-2 text-left font-mono text-xs tracking-wide text-[#6b6b6b] transition hover:bg-[#1a1a1a] hover:text-[#e5e5e5]"
            >
              {localeLabels[l]}
            </button>
          ))}
        </div>
      )}
      <button
        onClick={() => setOpen(!open)}
        className="flex h-9 items-center gap-1.5 rounded-lg border border-[#2a2a2a] bg-[#141414] px-3 font-mono text-xs tracking-wide text-[#6b6b6b] transition hover:border-[#3a3a3a] hover:text-[#e5e5e5]"
      >
        <svg width="14" height="14" viewBox="0 0 14 14" fill="none" className="opacity-50">
          <circle cx="7" cy="7" r="5.5" stroke="currentColor" strokeWidth="1" />
          <ellipse cx="7" cy="7" rx="2.5" ry="5.5" stroke="currentColor" strokeWidth="1" />
          <path d="M1.5 7H12.5" stroke="currentColor" strokeWidth="1" />
        </svg>
        {localeLabels[locale]}
      </button>
    </div>
  );
}
