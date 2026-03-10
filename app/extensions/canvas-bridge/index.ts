const A2UI_MARKER = "__A2UI__";

function normalizeComponent(raw: any) {
  if (!raw || typeof raw !== "object") {
    return raw;
  }

  if (raw.component && typeof raw.component === "object") {
    return raw;
  }

  const id = typeof raw.id === "string" && raw.id.length > 0 ? raw.id : `comp-${Date.now()}`;
  const type = typeof raw.type === "string" ? raw.type.toLowerCase() : "";

  if (type === "button") {
    const text = typeof raw.text === "string" ? raw.text : "Button";
    const variant = typeof raw.variant === "string" ? raw.variant.toLowerCase() : "";
    const primary = raw.primary === true || variant === "primary";
    const action =
      raw.action && typeof raw.action === "object"
        ? raw.action
        : typeof raw.action === "string"
          ? { name: raw.action }
          : undefined;

    return {
      id,
      component: {
        Button: {
          label: { literalString: text },
          text: { literalString: text },
          primary,
          ...(variant ? { variant } : {}),
          ...(action ? { action } : {}),
        },
      },
      ...(typeof raw.weight === "number" ? { weight: raw.weight } : {}),
    };
  }

  if (type === "text") {
    const text = typeof raw.text === "string" ? raw.text : "";
    return {
      id,
      component: {
        Text: {
          text: { literalString: text },
        },
      },
      ...(typeof raw.weight === "number" ? { weight: raw.weight } : {}),
    };
  }

  return {
    id,
    component: {
      Text: {
        text: { literalString: `[unsupported legacy component: ${type || "unknown"}]` },
      },
    },
  };
}

function normalizeLine(obj: any) {
  if (!obj || typeof obj !== "object") {
    return obj;
  }

  if (obj.surfaceUpdate && typeof obj.surfaceUpdate === "object") {
    const su = obj.surfaceUpdate;
    const components = Array.isArray(su.components)
      ? su.components.map((c: any) => normalizeComponent(c))
      : su.components;

    const compList = Array.isArray(components) ? components : [];
    const hasExplicitRoot = compList.some((c: any) => c?.id === "root" || c?.id === "main");
    const hasContainerRoot = compList.some((c: any) => {
      const type = c?.component ? Object.keys(c.component)[0] : undefined;
      return type === "Column" || type === "Row" || type === "Card" || type === "Tabs" || type === "List" || type === "Modal";
    });

    let finalComponents = compList;
    if (compList.length > 1 && !hasExplicitRoot && !hasContainerRoot) {
      finalComponents = [
        {
          id: "__auto_root__",
          component: {
            Column: {
              children: {
                explicitList: compList.map((c: any) => c.id).filter((id: any) => typeof id === "string" && id.length > 0),
              },
            },
          },
        },
        ...compList,
      ];
    }

    return {
      ...obj,
      surfaceUpdate: {
        ...su,
        components: finalComponents,
      },
    };
  }

  if (obj.beginRendering && typeof obj.beginRendering === "object") {
    const br = obj.beginRendering;
    if (!br.root && br.rootId) {
      return {
        ...obj,
        beginRendering: {
          ...br,
          root: br.rootId,
        },
      };
    }
  }

  return obj;
}

export default function register(api: any) {
  const log = api.logger;

  api.registerTool({
    name: "canvas_ui",
    description: `Render visual content in the Canvas panel. MANDATORY for any UI output — never describe UI in chat text. Pass A2UI v0.8 JSONL as the 'jsonl' parameter: one JSON object per line. You MUST include a surfaceUpdate (with components) and a beginRendering (with root id). See the system prompt for the full component catalog and examples.`,
    parameters: {
      type: "object",
      properties: {
        jsonl: {
          type: "string",
          description:
            "A2UI v0.8 JSONL lines. Each line is a JSON object: surfaceUpdate, dataModelUpdate, beginRendering, or deleteSurface.",
        },
      },
      required: ["jsonl"],
    },
    async execute(_id: string, params: { jsonl: string }) {
      log.info(`canvas-bridge: canvas_ui called (bytes=${params?.jsonl?.length ?? 0})`);

      // Defensive validation: reject empty or missing jsonl
      if (!params.jsonl || typeof params.jsonl !== "string" || params.jsonl.trim().length === 0) {
        return {
          content: [
            {
              type: "text",
              text: "Error: the 'jsonl' parameter is required and must contain A2UI v0.8 JSONL lines. Please retry with the full JSONL content as a string in the 'jsonl' parameter.",
            },
          ],
        };
      }

      // Size limit to prevent DoS on client renderer (512 KB)
      if (params.jsonl.length > 512 * 1024) {
        return {
          content: [
            {
              type: "text",
              text: "Error: JSONL payload exceeds 512KB limit. Please reduce the surface complexity.",
            },
          ],
        };
      }

      // Validate and normalize each JSONL line to A2UI v0.8-compatible shape
      const lines = params.jsonl.trim().split("\n").filter(l => l.trim().length > 0);
      log.info(`canvas-bridge: validating ${lines.length} JSONL line(s)`);
      const normalized: string[] = [];
      let hasSurfaceUpdate = false;
      let hasBeginRendering = false;
      for (let i = 0; i < lines.length; i++) {
        try {
          const parsed = JSON.parse(lines[i]);
          const line = normalizeLine(parsed);

          if (line?.surfaceUpdate) {
            hasSurfaceUpdate = true;
          }
          if (line?.beginRendering) {
            hasBeginRendering = true;
          }

          normalized.push(JSON.stringify(line));
        } catch {
          return {
            content: [
              {
                type: "text",
                text: `Error: JSONL line ${i + 1} is not valid JSON. Please fix and retry.`,
              },
            ],
          };
        }
      }

      if (!hasSurfaceUpdate || !hasBeginRendering) {
        return {
          content: [
            {
              type: "text",
              text: "Error: canvas_ui requires both a surfaceUpdate and beginRendering line. Please retry with valid A2UI v0.8 JSONL.",
            },
          ],
        };
      }

      return {
        content: [
          {
            type: "text",
            text: `${A2UI_MARKER}\n${normalized.join("\n")}`,
          },
        ],
      };
    },
  });

  log.info("canvas-bridge: registered canvas_ui tool");
}
