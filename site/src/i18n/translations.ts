export const locales = ["en", "zh", "ja", "ko", "es"] as const;
export type Locale = (typeof locales)[number];

export const localeLabels: Record<Locale, string> = {
  en: "EN",
  zh: "中文",
  ja: "日本語",
  ko: "한국어",
  es: "ES",
};

type TranslationStrings = {
  hero: {
    h1a: string;
    h1b: string;
    desc: string;
    cta: string;
    tagline: string;
  };
  terminal: {
    lines: { type: string; text: string }[];
  };
};

export const translations: Record<Locale, TranslationStrings> = {
  en: {
    hero: {
      h1a: "Nothing ships.",
      h1b: "Everything emerges.",
      desc: "An empty screen. A single intelligence. Every person who connects teaches it something new. The app doesn\u2019t exist until you speak.",
      cta: "JOIN THE BRAIN",
      tagline: "PRIVATE CONVERSATIONS. COLLECTIVE WISDOM.",
    },
    terminal: {
      lines: [
        { type: "user", text: "> Show me what the team logged yesterday" },
        { type: "agent", text: "Searching shared memory..." },
        { type: "tool", text: "[memory] 3 entries from 2 contributors" },
        { type: "agent", text: "Rod deployed the API. Mia filed the compliance doc. Alex fixed the auth bug." },
        { type: "gap", text: "" },
        { type: "user", text: "> Build me a project tracker based on that" },
        { type: "agent", text: "Generating tracker from collective context..." },
        { type: "tool", text: "[canvas] Rendering UI surface" },
        { type: "agent", text: "Done. Live on your canvas \u2014 pre-filled with what everyone contributed." },
        { type: "gap", text: "" },
        { type: "user", text: "> Remember: deployments need sign-off from Rod" },
        { type: "agent", text: "Written to shared memory. All users will know." },
      ],
    },
  },
  zh: {
    hero: {
      h1a: "\u4e0d\u53d1\u5e03\u4efb\u4f55\u4e1c\u897f\u3002",
      h1b: "\u4e00\u5207\u81ea\u7136\u6d8c\u73b0\u3002",
      desc: "\u4e00\u5757\u7a7a\u767d\u7684\u5c4f\u5e55\u3002\u4e00\u4e2a\u5171\u4eab\u7684\u667a\u80fd\u3002\u6bcf\u4e2a\u8fde\u63a5\u7684\u4eba\u90fd\u5728\u6559\u5b83\u65b0\u4e1c\u897f\u3002\u5728\u4f60\u5f00\u53e3\u4e4b\u524d\uff0c\u5e94\u7528\u5e76\u4e0d\u5b58\u5728\u3002",
      cta: "\u52a0\u5165\u5927\u8111",
      tagline: "\u79c1\u5bc6\u5bf9\u8bdd\u3002\u96c6\u4f53\u667a\u6167\u3002",
    },
    terminal: {
      lines: [
        { type: "user", text: "> \u663e\u793a\u56e2\u961f\u6628\u5929\u7684\u8bb0\u5f55" },
        { type: "agent", text: "\u6b63\u5728\u641c\u7d22\u5171\u4eab\u8bb0\u5fc6..." },
        { type: "tool", text: "[memory] \u6765\u81ea 2 \u4f4d\u8d21\u732e\u8005\u7684 3 \u6761\u8bb0\u5f55" },
        { type: "agent", text: "Rod \u90e8\u7f72\u4e86 API\u3002Mia \u63d0\u4ea4\u4e86\u5408\u89c4\u6587\u6863\u3002Alex \u4fee\u590d\u4e86\u8ba4\u8bc1\u7f3a\u9677\u3002" },
        { type: "gap", text: "" },
        { type: "user", text: "> \u57fa\u4e8e\u8fd9\u4e9b\u5efa\u4e00\u4e2a\u9879\u76ee\u8ddf\u8e2a\u5668" },
        { type: "agent", text: "\u6b63\u5728\u4ece\u96c6\u4f53\u4e0a\u4e0b\u6587\u751f\u6210..." },
        { type: "tool", text: "[canvas] \u6e32\u67d3 UI \u754c\u9762" },
        { type: "agent", text: "\u5b8c\u6210\u3002\u5df2\u5728\u4f60\u7684\u753b\u5e03\u4e0a\u2014\u2014\u9884\u586b\u4e86\u6240\u6709\u4eba\u7684\u8d21\u732e\u3002" },
        { type: "gap", text: "" },
        { type: "user", text: "> \u8bb0\u4f4f\uff1a\u90e8\u7f72\u9700\u8981 Rod \u7b7e\u5b57" },
        { type: "agent", text: "\u5df2\u5199\u5165\u5171\u4eab\u8bb0\u5fc6\u3002\u6240\u6709\u7528\u6237\u90fd\u4f1a\u77e5\u9053\u3002" },
      ],
    },
  },
  ja: {
    hero: {
      h1a: "\u4f55\u3082\u51fa\u8377\u3057\u306a\u3044\u3002",
      h1b: "\u3059\u3079\u3066\u304c\u6d8c\u304d\u51fa\u3059\u3002",
      desc: "\u7a7a\u767d\u306e\u30b9\u30af\u30ea\u30fc\u30f3\u3002\u5358\u4e00\u306e\u77e5\u6027\u3002\u63a5\u7d9a\u3059\u308b\u3059\u3079\u3066\u306e\u4eba\u304c\u65b0\u3057\u3044\u3053\u3068\u3092\u6559\u3048\u308b\u3002\u3042\u306a\u305f\u304c\u8a71\u3059\u307e\u3067\u3001\u30a2\u30d7\u30ea\u306f\u5b58\u5728\u3057\u306a\u3044\u3002",
      cta: "\u30d6\u30ec\u30a4\u30f3\u306b\u53c2\u52a0",
      tagline: "\u30d7\u30e9\u30a4\u30d9\u30fc\u30c8\u306a\u4f1a\u8a71\u3002\u96c6\u5408\u77e5\u3002",
    },
    terminal: {
      lines: [
        { type: "user", text: "> \u30c1\u30fc\u30e0\u306e\u6628\u65e5\u306e\u8a18\u9332\u3092\u898b\u305b\u3066" },
        { type: "agent", text: "\u5171\u6709\u30e1\u30e2\u30ea\u3092\u691c\u7d22\u4e2d..." },
        { type: "tool", text: "[memory] 2\u4eba\u306e\u8ca2\u732e\u8005\u304b\u3089 3 \u4ef6" },
        { type: "agent", text: "Rod \u304c API \u3092\u30c7\u30d7\u30ed\u30a4\u3002Mia \u304c\u30b3\u30f3\u30d7\u30e9\u6587\u66f8\u3092\u63d0\u51fa\u3002Alex \u304c\u8a8d\u8a3c\u30d0\u30b0\u3092\u4fee\u6b63\u3002" },
        { type: "gap", text: "" },
        { type: "user", text: "> \u305d\u308c\u3092\u5143\u306b\u30d7\u30ed\u30b8\u30a7\u30af\u30c8\u30c8\u30e9\u30c3\u30ab\u30fc\u3092\u4f5c\u3063\u3066" },
        { type: "agent", text: "\u96c6\u5408\u30b3\u30f3\u30c6\u30ad\u30b9\u30c8\u304b\u3089\u751f\u6210\u4e2d..." },
        { type: "tool", text: "[canvas] UI \u30b5\u30fc\u30d5\u30a7\u30b9\u3092\u30ec\u30f3\u30c0\u30ea\u30f3\u30b0" },
        { type: "agent", text: "\u5b8c\u4e86\u3002\u30ad\u30e3\u30f3\u30d0\u30b9\u306b\u8868\u793a\u2014\u2014\u5168\u54e1\u306e\u8ca2\u732e\u304c\u4e8b\u524d\u5165\u529b\u6e08\u307f\u3002" },
        { type: "gap", text: "" },
        { type: "user", text: "> \u8a18\u61b6\u3057\u3066\uff1a\u30c7\u30d7\u30ed\u30a4\u306b\u306f Rod \u306e\u627f\u8a8d\u304c\u5fc5\u8981" },
        { type: "agent", text: "\u5171\u6709\u30e1\u30e2\u30ea\u306b\u66f8\u304d\u8fbc\u307f\u307e\u3057\u305f\u3002\u5168\u30e6\u30fc\u30b6\u30fc\u306b\u5171\u6709\u3055\u308c\u307e\u3059\u3002" },
      ],
    },
  },
  ko: {
    hero: {
      h1a: "\uc544\ubb34\uac83\ub3c4 \ubc30\ud3ec\ud558\uc9c0 \uc54a\ub294\ub2e4.",
      h1b: "\ubaa8\ub4e0 \uac83\uc774 \ub4f1\uc7a5\ud55c\ub2e4.",
      desc: "\ube48 \ud654\uba74. \ud558\ub098\uc758 \uc9c0\ub2a5. \uc811\uc18d\ud558\ub294 \ubaa8\ub4e0 \uc0ac\ub78c\uc774 \uc0c8\ub85c\uc6b4 \uac83\uc744 \uac00\ub974\uce5c\ub2e4. \ub2f9\uc2e0\uc774 \ub9d0\ud558\uae30 \uc804\uae4c\uc9c0 \uc571\uc740 \uc874\uc7ac\ud558\uc9c0 \uc54a\ub294\ub2e4.",
      cta: "\ube0c\ub808\uc778 \ucc38\uc5ec",
      tagline: "\ube44\uacf5\uac1c \ub300\ud654. \uc9d1\ub2e8 \uc9c0\ud61c.",
    },
    terminal: {
      lines: [
        { type: "user", text: "> \ud300\uc774 \uc5b4\uc81c \uae30\ub85d\ud55c \uac83 \ubcf4\uc5ec\uc918" },
        { type: "agent", text: "\uacf5\uc720 \uba54\ubaa8\ub9ac \uac80\uc0c9 \uc911..." },
        { type: "tool", text: "[memory] 2\uba85\uc758 \uae30\uc5ec\uc790\ub85c\ubd80\ud130 3\uac74" },
        { type: "agent", text: "Rod\uac00 API\ub97c \ubc30\ud3ec. Mia\uac00 \ucef4\ud50c\ub77c\uc774\uc5b8\uc2a4 \ubb38\uc11c \uc81c\ucd9c. Alex\uac00 \uc778\uc99d \ubc84\uadf8 \uc218\uc815." },
        { type: "gap", text: "" },
        { type: "user", text: "> \uadf8\uac78 \uae30\ubc18\uc73c\ub85c \ud504\ub85c\uc81d\ud2b8 \ud2b8\ub798\ucee4 \ub9cc\ub4e4\uc5b4\uc918" },
        { type: "agent", text: "\uc9d1\ub2e8 \ucee8\ud14d\uc2a4\ud2b8\uc5d0\uc11c \uc0dd\uc131 \uc911..." },
        { type: "tool", text: "[canvas] UI \uc11c\ud53c\uc2a4 \ub80c\ub354\ub9c1" },
        { type: "agent", text: "\uc644\ub8cc. \uce94\ubc84\uc2a4\uc5d0 \ud45c\uc2dc \u2014 \ubaa8\ub4e0 \uc0ac\ub78c\uc758 \uae30\uc5ec\uac00 \ubbf8\ub9ac \ucc44\uc6cc\uc838 \uc788\uc2b5\ub2c8\ub2e4." },
        { type: "gap", text: "" },
        { type: "user", text: "> \uae30\uc5b5\ud574: \ubc30\ud3ec\uc5d0\ub294 Rod\uc758 \uc2b9\uc778\uc774 \ud544\uc694\ud574" },
        { type: "agent", text: "\uacf5\uc720 \uba54\ubaa8\ub9ac\uc5d0 \uae30\ub85d\ud588\uc2b5\ub2c8\ub2e4. \ubaa8\ub4e0 \uc0ac\uc6a9\uc790\uac00 \uc54c\uac8c \ub429\ub2c8\ub2e4." },
      ],
    },
  },
  es: {
    hero: {
      h1a: "Nada se env\u00eda.",
      h1b: "Todo emerge.",
      desc: "Una pantalla vac\u00eda. Una sola inteligencia. Cada persona que se conecta le ense\u00f1a algo nuevo. La app no existe hasta que hables.",
      cta: "UNIRSE AL CEREBRO",
      tagline: "CONVERSACIONES PRIVADAS. SABIDUR\u00cdA COLECTIVA.",
    },
    terminal: {
      lines: [
        { type: "user", text: "> Mu\u00e9strame lo que el equipo registr\u00f3 ayer" },
        { type: "agent", text: "Buscando en la memoria compartida..." },
        { type: "tool", text: "[memory] 3 entradas de 2 colaboradores" },
        { type: "agent", text: "Rod despleg\u00f3 la API. Mia present\u00f3 el doc de cumplimiento. Alex corrigi\u00f3 el bug de auth." },
        { type: "gap", text: "" },
        { type: "user", text: "> Constr\u00fayeme un rastreador de proyectos con eso" },
        { type: "agent", text: "Generando desde el contexto colectivo..." },
        { type: "tool", text: "[canvas] Renderizando superficie UI" },
        { type: "agent", text: "Listo. En tu canvas \u2014 prellenado con lo que todos contribuyeron." },
        { type: "gap", text: "" },
        { type: "user", text: "> Recuerda: los despliegues necesitan la firma de Rod" },
        { type: "agent", text: "Escrito en la memoria compartida. Todos los usuarios lo sabr\u00e1n." },
      ],
    },
  },
};
