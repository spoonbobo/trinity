export const locales = ["en", "zh-TW", "zh-CN"] as const;
export type Locale = (typeof locales)[number];

export const localeLabels: Record<Locale, string> = {
  en: "EN",
  "zh-TW": "繁體",
  "zh-CN": "简体",
};

type Pillar = { icon: string; label: string; desc: string };
type Step = { num: string; title: string; desc: string };
type Arch = { label: string; detail: string };
type Card = { icon: string; title: string; desc: string };

type TranslationStrings = {
  hero: {
    h1a: string;
    h1b: string;
    desc: string;
    cta: string;
    tagline: string;
    pillars: Pillar[];
  };
  how: {
    label: string;
    h2a: string;
    h2b: string;
    steps: Step[];
    archLabel: string;
    arch: Arch[];
  };
  why: {
    label: string;
    h2a: string;
    h2b: string;
    subtitle: string;
    cards: Card[];
    quote: string;
  };
};

export const translations: Record<Locale, TranslationStrings> = {
  en: {
    hero: {
      h1a: "Nothing ships.",
      h1b: "Everything emerges.",
      desc: "An empty screen. A single intelligence. Every person who connects teaches it something new. The system doesn\u2019t exist until you speak.",
      cta: "SEE HOW IT WORKS",
      tagline: "PRIVATE CONVERSATIONS. COLLECTIVE WISDOM.",
      pillars: [
        {
          icon: "\u25A1",
          label: "EMPTY BY DESIGN",
          desc: "No dashboards. No menus. The blank screen is the product.",
        },
        {
          icon: "\u2666",
          label: "BUILT BY CONVERSATION",
          desc: "You describe what you need. The agent assembles it in real time.",
        },
        {
          icon: "\u2731",
          label: "GROWS WITH EVERY USER",
          desc: "One brain absorbs everything. The more people use it, the smarter it gets.",
        },
      ],
    },
    how: {
      label: "HOW IT WORKS",
      h2a: "One intelligence.",
      h2b: "Many minds.",
      steps: [
        {
          num: "01",
          title: "You open a blank screen.",
          desc: "No dashboard. No sidebar. No onboarding wizard. Just a dark canvas and a prompt bar. The emptiness is the point.",
        },
        {
          num: "02",
          title: "You speak. It materializes.",
          desc: "Ask for anything \u2014 a tracker, a workflow, a tool. The agent generates the interface on the fly. No code. No config. Just intent.",
        },
        {
          num: "03",
          title: "Everyone feeds the same brain.",
          desc: "Every user has a private session. But the knowledge \u2014 memory, skills, decisions \u2014 accumulates in one place. The more people use it, the smarter it gets.",
        },
      ],
      archLabel: "ARCHITECTURE",
      arch: [
        {
          label: "Single OpenClaw Brain",
          detail: "One agent engine \u2014 shared memory, skills, and knowledge across all users",
        },
        {
          label: "Empty Shell",
          detail: "Blank canvas that renders whatever the intelligence produces \u2014 nothing more",
        },
        {
          label: "Any Channel In",
          detail: "Web, WhatsApp, Telegram, Discord \u2014 all feeding the same brain",
        },
      ],
    },
    why: {
      label: "WHY IT MATTERS",
      h2a: "Every fixed product is",
      h2b: "a cage.",
      subtitle: "Software today is someone else\u2019s opinion of what you need, frozen in code, behind a subscription. Trinity flips that entirely.",
      cards: [
        {
          icon: "\u2716",
          title: "Kills the feature roadmap",
          desc: "No team debates what to build next. Every user gets a different workspace shaped by their own needs. There\u2019s no one-size-fits-all because there\u2019s no fixed mold at all.",
        },
        {
          icon: "\u2261",
          title: "Replaces your tool stack",
          desc: "Jira, Confluence, Grafana, Retool, admin panels \u2014 each a separate product with its own limits. Here, every tool is a prompt away.",
        },
        {
          icon: "\u2690",
          title: "A living knowledge base",
          desc: "Not a static wiki nobody updates. Every conversation is context the system absorbs. It never goes stale, you don\u2019t search it \u2014 you ask it, and it can act on what it knows.",
        },
        {
          icon: "\u2263",
          title: "Governed by design",
          desc: "The agent can\u2019t silently break things. High-risk actions go through approval gates. Organizational hierarchy expressed through the agent, not a ticketing system.",
        },
        {
          icon: "\u2302",
          title: "Self-hosted. Your data.",
          desc: "Runs on your infrastructure. No vendor dependency, no data leaving your control, no pricing tier that gates what you need. You own the brain.",
        },
        {
          icon: "\u2194",
          title: "Talk from anywhere",
          desc: "Same brain on the web shell, WhatsApp, Telegram, Discord, mobile nodes. The command center is for complex tasks. For quick ones, just text it from your phone.",
        },
      ],
      quote: "\u201COnce you internalize this model, every fixed product feels like an unnecessary constraint. Why accept someone else\u2019s limits when you can describe what you want and watch it materialize?\u201D",
    },
  },

  "zh-TW": {
    hero: {
      h1a: "\u4e0d\u767c\u4f48\u4efb\u4f55\u6771\u897f\u3002",
      h1b: "\u4e00\u5207\u81ea\u7136\u6d8c\u73fe\u3002",
      desc: "\u4e00\u584a\u7a7a\u767d\u7684\u87a2\u5e55\u3002\u4e00\u500b\u5171\u4eab\u7684\u667a\u80fd\u3002\u6bcf\u500b\u9023\u63a5\u7684\u4eba\u90fd\u5728\u6559\u5b83\u65b0\u6771\u897f\u3002\u5728\u4f60\u958b\u53e3\u4e4b\u524d\uff0c\u61c9\u7528\u4e26\u4e0d\u5b58\u5728\u3002",
      cta: "\u770b\u770b\u600e\u9ebc\u904b\u4f5c",
      tagline: "\u79c1\u5bc6\u5c0d\u8a71\u3002\u96c6\u9ad4\u667a\u6167\u3002",
      pillars: [
        {
          icon: "\u25A1",
          label: "\u7a7a\u767d\u5373\u7522\u54c1",
          desc: "\u6c92\u6709\u5100\u8868\u677f\u3002\u6c92\u6709\u9078\u55ae\u3002\u7a7a\u767d\u87a2\u5e55\u5c31\u662f\u7522\u54c1\u672c\u8eab\u3002",
        },
        {
          icon: "\u2666",
          label: "\u5c0d\u8a71\u5373\u5efa\u9020",
          desc: "\u63cf\u8ff0\u4f60\u9700\u8981\u7684\u3002\u667a\u80fd\u9ad4\u5373\u6642\u5efa\u9020\u3002",
        },
        {
          icon: "\u2731",
          label: "\u8d8a\u7528\u8d8a\u8070\u660e",
          desc: "\u4e00\u500b\u5927\u8166\u5438\u6536\u4e00\u5207\u3002\u4f7f\u7528\u7684\u4eba\u8d8a\u591a\uff0c\u5b83\u5c31\u8d8a\u8070\u660e\u3002",
        },
      ],
    },
    how: {
      label: "\u904b\u4f5c\u65b9\u5f0f",
      h2a: "\u4e00\u500b\u667a\u80fd\u3002",
      h2b: "\u8a31\u591a\u5fc3\u667a\u3002",
      steps: [
        {
          num: "01",
          title: "\u4f60\u6253\u958b\u4e00\u584a\u7a7a\u767d\u87a2\u5e55\u3002",
          desc: "\u6c92\u6709\u5100\u8868\u677f\u3001\u6c92\u6709\u5074\u6b04\u3001\u6c92\u6709\u5f15\u5c0e\u7cbe\u9748\u3002\u53ea\u6709\u9ed1\u6697\u7684\u756b\u5e03\u548c\u4e00\u500b\u63d0\u793a\u5217\u3002\u7a7a\u767d\u5c31\u662f\u91cd\u9ede\u3002",
        },
        {
          num: "02",
          title: "\u4f60\u8aaa\u8a71\u3002\u5b83\u5efa\u9020\u3002",
          desc: "\u8981\u6c42\u4efb\u4f55\u6771\u897f\u2014\u2014\u8ffd\u8e64\u5668\u3001\u5de5\u4f5c\u6d41\u3001\u5de5\u5177\u3002\u667a\u80fd\u9ad4\u5373\u6642\u7522\u751f\u4ecb\u9762\u3002\u4e0d\u9700\u8981\u5beb\u7a0b\u5f0f\u3002\u53ea\u9700\u8981\u610f\u5716\u3002",
        },
        {
          num: "03",
          title: "\u6bcf\u500b\u4eba\u990a\u540c\u4e00\u500b\u5927\u8166\u3002",
          desc: "\u6bcf\u500b\u4f7f\u7528\u8005\u6709\u79c1\u4eba\u6703\u8a71\u3002\u4f46\u77e5\u8b58\u2014\u2014\u8a18\u61b6\u3001\u6280\u80fd\u3001\u6c7a\u7b56\u2014\u2014\u7d2f\u7a4d\u5728\u540c\u4e00\u8655\u3002\u4f7f\u7528\u7684\u4eba\u8d8a\u591a\uff0c\u5b83\u5c31\u8d8a\u8070\u660e\u3002",
        },
      ],
      archLabel: "\u67b6\u69cb",
      arch: [
        {
          label: "\u55ae\u4e00 OpenClaw \u5927\u8166",
          detail: "\u4e00\u500b\u667a\u80fd\u5f15\u64ce\u2014\u2014\u6240\u6709\u4f7f\u7528\u8005\u5171\u4eab\u8a18\u61b6\u3001\u6280\u80fd\u548c\u77e5\u8b58",
        },
        {
          label: "\u7a7a\u767d\u5916\u6bbc",
          detail: "\u7a7a\u767d\u756b\u5e03\u53ea\u6e32\u67d3\u667a\u80fd\u7522\u751f\u7684\u5167\u5bb9\u2014\u2014\u50c5\u6b64\u800c\u5df2",
        },
        {
          label: "\u4efb\u4f55\u983b\u9053\u63a5\u5165",
          detail: "\u7db2\u9801\u3001WhatsApp\u3001Telegram\u3001Discord\u2014\u2014\u5168\u90e8\u9935\u5165\u540c\u4e00\u500b\u5927\u8166",
        },
      ],
    },
    why: {
      label: "\u70ba\u4ec0\u9ebc\u91cd\u8981",
      h2a: "\u6bcf\u500b\u5176\u4ed6\u61c9\u7528\u90fd\u662f",
      h2b: "\u4e00\u500b\u7c60\u5b50\u3002",
      subtitle: "\u4eca\u5929\u7684\u8edf\u9ad4\u662f\u5225\u4eba\u5c0d\u4f60\u9700\u6c42\u7684\u770b\u6cd5\uff0c\u51cd\u7d50\u5728\u7a0b\u5f0f\u78bc\u88e1\uff0c\u85cf\u5728\u8a02\u95b1\u5236\u5f8c\u9762\u3002Trinity \u5b8c\u5168\u7ffb\u8f49\u4e86\u9019\u4e00\u5207\u3002",
      cards: [
        {
          icon: "\u2716",
          title: "\u6bba\u6b7b\u529f\u80fd\u8def\u7dda\u5716",
          desc: "\u6c92\u6709\u5718\u968a\u7232\u4e0b\u4e00\u6b65\u5efa\u4ec0\u9ebc\u800c\u722d\u8ad6\u3002\u6bcf\u500b\u4f7f\u7528\u8005\u5f97\u5230\u4e00\u500b\u7531\u81ea\u5df1\u9700\u6c42\u5851\u9020\u7684\u4e0d\u540c\u61c9\u7528\u3002",
        },
        {
          icon: "\u2261",
          title: "\u53d6\u4ee3\u4f60\u7684\u5de5\u5177\u5806\u758a",
          desc: "Jira\u3001Confluence\u3001Grafana\u3001Retool\u3001\u7ba1\u7406\u5f8c\u53f0\u2014\u2014\u6bcf\u500b\u90fd\u662f\u6709\u81ea\u5df1\u9650\u5236\u7684\u7368\u7acb\u7522\u54c1\u3002\u5728\u9019\u88e1\uff0c\u6bcf\u500b\u5de5\u5177\u90fd\u53ea\u662f\u4e00\u53e5\u63d0\u793a\u3002",
        },
        {
          icon: "\u2690",
          title: "\u6d3b\u7684\u77e5\u8b58\u5eab",
          desc: "\u4e0d\u662f\u6c92\u4eba\u66f4\u65b0\u7684\u975c\u614b wiki\u3002\u6bcf\u6b21\u5c0d\u8a71\u90fd\u662f\u7cfb\u7d71\u5438\u6536\u7684\u4e0a\u4e0b\u6587\u3002\u5b83\u6c38\u9060\u4e0d\u6703\u904e\u6642\uff0c\u4f60\u4e0d\u7528\u641c\u5c0b\u2014\u2014\u4f60\u554f\u5b83\uff0c\u5b83\u80fd\u57f7\u884c\u3002",
        },
        {
          icon: "\u2263",
          title: "\u5167\u5efa\u6cbb\u7406",
          desc: "\u667a\u80fd\u9ad4\u4e0d\u80fd\u9748\u9ed8\u5730\u7834\u58de\u6771\u897f\u3002\u9ad8\u98a8\u96aa\u64cd\u4f5c\u901a\u904e\u5be9\u6279\u9580\u3002\u7d44\u7e54\u968e\u5c64\u900f\u904e\u667a\u80fd\u9ad4\u8868\u9054\uff0c\u4e0d\u662f\u5de5\u55ae\u7cfb\u7d71\u3002",
        },
        {
          icon: "\u2302",
          title: "\u81ea\u67b6\u3002\u4f60\u7684\u8cc7\u6599\u3002",
          desc: "\u5728\u4f60\u7684\u57fa\u790e\u8a2d\u65bd\u4e0a\u57f7\u884c\u3002\u6c92\u6709\u4f9b\u61c9\u5546\u4f9d\u8cf4\uff0c\u8cc7\u6599\u4e0d\u6703\u96e2\u958b\u4f60\u7684\u63a7\u5236\uff0c\u4f60\u64c1\u6709\u5927\u8166\u3002",
        },
        {
          icon: "\u2194",
          title: "\u96a8\u8655\u4ea4\u8ac7",
          desc: "\u7db2\u9801\u3001WhatsApp\u3001Telegram\u3001Discord\u3001\u624b\u6a5f\u7bc0\u9ede\u90fd\u662f\u540c\u4e00\u500b\u5927\u8166\u3002\u6307\u63ee\u4e2d\u5fc3\u7528\u65bc\u8907\u96dc\u4efb\u52d9\u3002\u7c21\u55ae\u7684\uff0c\u76f4\u63a5\u5f9e\u624b\u6a5f\u50b3\u8a0a\u606f\u3002",
        },
      ],
      quote: "\u300c\u4e00\u65e6\u4f60\u5167\u5316\u4e86\u9019\u500b\u6a21\u5f0f\uff0c\u6bcf\u500b\u50b3\u7d71\u61c9\u7528\u90fd\u611f\u89ba\u50cf\u4e0d\u5fc5\u8981\u7684\u675f\u7e1b\u3002\u70ba\u4ec0\u9ebc\u8981\u7528\u5225\u4eba\u7684\u9650\u5236\u6253\u9020\u7684\u5de5\u5177\uff0c\u800c\u4e0d\u662f\u63cf\u8ff0\u4f60\u8981\u7684\uff0c\u8b93\u5b83\u5be6\u9ad4\u5316\uff1f\u300d",
    },
  },

  "zh-CN": {
    hero: {
      h1a: "\u4e0d\u53d1\u5e03\u4efb\u4f55\u4e1c\u897f\u3002",
      h1b: "\u4e00\u5207\u81ea\u7136\u6d8c\u73b0\u3002",
      desc: "\u4e00\u5757\u7a7a\u767d\u7684\u5c4f\u5e55\u3002\u4e00\u4e2a\u5171\u4eab\u7684\u667a\u80fd\u3002\u6bcf\u4e2a\u8fde\u63a5\u7684\u4eba\u90fd\u5728\u6559\u5b83\u65b0\u4e1c\u897f\u3002\u5728\u4f60\u5f00\u53e3\u4e4b\u524d\uff0c\u5e94\u7528\u5e76\u4e0d\u5b58\u5728\u3002",
      cta: "\u770b\u770b\u600e\u4e48\u8fd0\u4f5c",
      tagline: "\u79c1\u5bc6\u5bf9\u8bdd\u3002\u96c6\u4f53\u667a\u6167\u3002",
      pillars: [
        {
          icon: "\u25A1",
          label: "\u7a7a\u767d\u5373\u4ea7\u54c1",
          desc: "\u6ca1\u6709\u4eea\u8868\u76d8\u3002\u6ca1\u6709\u83dc\u5355\u3002\u7a7a\u767d\u5c4f\u5e55\u5c31\u662f\u4ea7\u54c1\u672c\u8eab\u3002",
        },
        {
          icon: "\u2666",
          label: "\u5bf9\u8bdd\u5373\u5efa\u9020",
          desc: "\u63cf\u8ff0\u4f60\u9700\u8981\u7684\u3002\u667a\u80fd\u4f53\u5b9e\u65f6\u5efa\u9020\u3002",
        },
        {
          icon: "\u2731",
          label: "\u8d8a\u7528\u8d8a\u806a\u660e",
          desc: "\u4e00\u4e2a\u5927\u8111\u5438\u6536\u4e00\u5207\u3002\u4f7f\u7528\u7684\u4eba\u8d8a\u591a\uff0c\u5b83\u5c31\u8d8a\u806a\u660e\u3002",
        },
      ],
    },
    how: {
      label: "\u8fd0\u4f5c\u65b9\u5f0f",
      h2a: "\u4e00\u4e2a\u667a\u80fd\u3002",
      h2b: "\u8bb8\u591a\u5fc3\u667a\u3002",
      steps: [
        {
          num: "01",
          title: "\u4f60\u6253\u5f00\u4e00\u5757\u7a7a\u767d\u5c4f\u5e55\u3002",
          desc: "\u6ca1\u6709\u4eea\u8868\u76d8\u3001\u6ca1\u6709\u4fa7\u680f\u3001\u6ca1\u6709\u5f15\u5bfc\u7cbe\u7075\u3002\u53ea\u6709\u9ed1\u6697\u7684\u753b\u5e03\u548c\u4e00\u4e2a\u63d0\u793a\u680f\u3002\u7a7a\u767d\u5c31\u662f\u91cd\u70b9\u3002",
        },
        {
          num: "02",
          title: "\u4f60\u8bf4\u8bdd\u3002\u5b83\u5efa\u9020\u3002",
          desc: "\u8981\u6c42\u4efb\u4f55\u4e1c\u897f\u2014\u2014\u8ddf\u8e2a\u5668\u3001\u5de5\u4f5c\u6d41\u3001\u5de5\u5177\u3002\u667a\u80fd\u4f53\u5b9e\u65f6\u751f\u6210\u754c\u9762\u3002\u4e0d\u9700\u8981\u5199\u4ee3\u7801\u3002\u53ea\u9700\u8981\u610f\u56fe\u3002",
        },
        {
          num: "03",
          title: "\u6bcf\u4e2a\u4eba\u517b\u540c\u4e00\u4e2a\u5927\u8111\u3002",
          desc: "\u6bcf\u4e2a\u7528\u6237\u6709\u79c1\u4eba\u4f1a\u8bdd\u3002\u4f46\u77e5\u8bc6\u2014\u2014\u8bb0\u5fc6\u3001\u6280\u80fd\u3001\u51b3\u7b56\u2014\u2014\u7d2f\u79ef\u5728\u540c\u4e00\u5904\u3002\u4f7f\u7528\u7684\u4eba\u8d8a\u591a\uff0c\u5b83\u5c31\u8d8a\u806a\u660e\u3002",
        },
      ],
      archLabel: "\u67b6\u6784",
      arch: [
        {
          label: "\u5355\u4e00 OpenClaw \u5927\u8111",
          detail: "\u4e00\u4e2a\u667a\u80fd\u5f15\u64ce\u2014\u2014\u6240\u6709\u7528\u6237\u5171\u4eab\u8bb0\u5fc6\u3001\u6280\u80fd\u548c\u77e5\u8bc6",
        },
        {
          label: "\u7a7a\u767d\u5916\u58f3",
          detail: "\u7a7a\u767d\u753b\u5e03\u53ea\u6e32\u67d3\u667a\u80fd\u4ea7\u751f\u7684\u5185\u5bb9\u2014\u2014\u4ec5\u6b64\u800c\u5df2",
        },
        {
          label: "\u4efb\u4f55\u9891\u9053\u63a5\u5165",
          detail: "\u7f51\u9875\u3001WhatsApp\u3001Telegram\u3001Discord\u2014\u2014\u5168\u90e8\u9a71\u5165\u540c\u4e00\u4e2a\u5927\u8111",
        },
      ],
    },
    why: {
      label: "\u4e3a\u4ec0\u4e48\u91cd\u8981",
      h2a: "\u6bcf\u4e2a\u5176\u4ed6\u5e94\u7528\u90fd\u662f",
      h2b: "\u4e00\u4e2a\u7b3c\u5b50\u3002",
      subtitle: "\u4eca\u5929\u7684\u8f6f\u4ef6\u662f\u522b\u4eba\u5bf9\u4f60\u9700\u6c42\u7684\u770b\u6cd5\uff0c\u51bb\u7ed3\u5728\u4ee3\u7801\u91cc\uff0c\u85cf\u5728\u8ba2\u9605\u5236\u540e\u9762\u3002Trinity \u5b8c\u5168\u7ffb\u8f6c\u4e86\u8fd9\u4e00\u5207\u3002",
      cards: [
        {
          icon: "\u2716",
          title: "\u6740\u6b7b\u529f\u80fd\u8def\u7ebf\u56fe",
          desc: "\u6ca1\u6709\u56e2\u961f\u4e3a\u4e0b\u4e00\u6b65\u5efa\u4ec0\u4e48\u800c\u4e89\u8bba\u3002\u6bcf\u4e2a\u7528\u6237\u5f97\u5230\u4e00\u4e2a\u7531\u81ea\u5df1\u9700\u6c42\u5851\u9020\u7684\u4e0d\u540c\u5e94\u7528\u3002",
        },
        {
          icon: "\u2261",
          title: "\u53d6\u4ee3\u4f60\u7684\u5de5\u5177\u5806\u53e0",
          desc: "Jira\u3001Confluence\u3001Grafana\u3001Retool\u3001\u7ba1\u7406\u540e\u53f0\u2014\u2014\u6bcf\u4e2a\u90fd\u662f\u6709\u81ea\u5df1\u9650\u5236\u7684\u72ec\u7acb\u4ea7\u54c1\u3002\u5728\u8fd9\u91cc\uff0c\u6bcf\u4e2a\u5de5\u5177\u90fd\u53ea\u662f\u4e00\u53e5\u63d0\u793a\u3002",
        },
        {
          icon: "\u2690",
          title: "\u6d3b\u7684\u77e5\u8bc6\u5e93",
          desc: "\u4e0d\u662f\u6ca1\u4eba\u66f4\u65b0\u7684\u9759\u6001 wiki\u3002\u6bcf\u6b21\u5bf9\u8bdd\u90fd\u662f\u7cfb\u7edf\u5438\u6536\u7684\u4e0a\u4e0b\u6587\u3002\u5b83\u6c38\u8fdc\u4e0d\u4f1a\u8fc7\u65f6\uff0c\u4f60\u4e0d\u7528\u641c\u7d22\u2014\u2014\u4f60\u95ee\u5b83\uff0c\u5b83\u80fd\u6267\u884c\u3002",
        },
        {
          icon: "\u2263",
          title: "\u5185\u5efa\u6cbb\u7406",
          desc: "\u667a\u80fd\u4f53\u4e0d\u80fd\u9759\u9ed8\u5730\u7834\u574f\u4e1c\u897f\u3002\u9ad8\u98ce\u9669\u64cd\u4f5c\u901a\u8fc7\u5ba1\u6279\u95e8\u3002\u7ec4\u7ec7\u5c42\u7ea7\u901a\u8fc7\u667a\u80fd\u4f53\u8868\u8fbe\uff0c\u4e0d\u662f\u5de5\u5355\u7cfb\u7edf\u3002",
        },
        {
          icon: "\u2302",
          title: "\u81ea\u67b6\u3002\u4f60\u7684\u6570\u636e\u3002",
          desc: "\u5728\u4f60\u7684\u57fa\u7840\u8bbe\u65bd\u4e0a\u8fd0\u884c\u3002\u6ca1\u6709\u4f9b\u5e94\u5546\u4f9d\u8d56\uff0c\u6570\u636e\u4e0d\u4f1a\u79bb\u5f00\u4f60\u7684\u63a7\u5236\uff0c\u4f60\u62e5\u6709\u5927\u8111\u3002",
        },
        {
          icon: "\u2194",
          title: "\u968f\u5904\u4ea4\u8c08",
          desc: "\u7f51\u9875\u3001WhatsApp\u3001Telegram\u3001Discord\u3001\u624b\u673a\u8282\u70b9\u90fd\u662f\u540c\u4e00\u4e2a\u5927\u8111\u3002\u6307\u6325\u4e2d\u5fc3\u7528\u4e8e\u590d\u6742\u4efb\u52a1\u3002\u7b80\u5355\u7684\uff0c\u76f4\u63a5\u4ece\u624b\u673a\u53d1\u6d88\u606f\u3002",
        },
      ],
      quote: "\u201c\u4e00\u65e6\u4f60\u5185\u5316\u4e86\u8fd9\u4e2a\u6a21\u5f0f\uff0c\u6bcf\u4e2a\u4f20\u7edf\u5e94\u7528\u90fd\u611f\u89c9\u50cf\u4e0d\u5fc5\u8981\u7684\u675f\u7f1a\u3002\u4e3a\u4ec0\u4e48\u8981\u7528\u522b\u4eba\u7684\u9650\u5236\u6253\u9020\u7684\u5de5\u5177\uff0c\u800c\u4e0d\u662f\u63cf\u8ff0\u4f60\u8981\u7684\uff0c\u8ba9\u5b83\u5b9e\u4f53\u5316\uff1f\u201d",
    },
  },
};
