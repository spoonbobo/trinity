const A2UI_MARKER = "__A2UI__";

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

      // Validate that each line is parseable JSON
      const lines = params.jsonl.trim().split("\n").filter(l => l.trim().length > 0);
      log.info(`canvas-bridge: validating ${lines.length} JSONL line(s)`);
      for (let i = 0; i < lines.length; i++) {
        try {
          JSON.parse(lines[i]);
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

      return {
        content: [
          {
            type: "text",
            text: `${A2UI_MARKER}\n${params.jsonl}`,
          },
        ],
      };
    },
  });

  log.info("canvas-bridge: registered canvas_ui tool");
}
