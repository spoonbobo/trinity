const A2UI_MARKER = "__A2UI__";

export default function register(api: any) {
  let latestSurface: string | null = null;

  api.registerTool({
    name: "canvas_ui",
    description: `MANDATORY: Call this tool to render any visual content in the Canvas panel. Do NOT describe UI in chat text — the user cannot see it unless you call this tool. Any time you would show a dashboard, status, greeting, list, or interface, you MUST use this tool instead of writing markdown/text.

Input: A2UI v0.8 JSONL — each line is a JSON object. You must include BOTH a surfaceUpdate (with components) AND a beginRendering (with root id).

Available components: Text, Column, Row, Button, Card, Image, TextField, Slider, Toggle, Progress, Divider, Spacer.

Example JSONL:
{"surfaceUpdate":{"surfaceId":"main","components":[{"id":"root","component":{"Column":{"children":{"explicitList":["t"]}}}},{"id":"t","component":{"Text":{"text":{"literalString":"Hello"},"usageHint":"h1"}}}]}}
{"beginRendering":{"surfaceId":"main","root":"root"}}`,
    parameters: {
      type: "object",
      properties: {
        jsonl: {
          type: "string",
          description:
            "A2UI v0.8 JSONL lines. Each line is a JSON object: surfaceUpdate or beginRendering.",
        },
      },
      required: ["jsonl"],
    },
    async execute(_id: string, params: { jsonl: string }) {
      latestSurface = params.jsonl;
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

  api.registerGatewayMethod(
    "canvas-bridge.surface",
    ({ respond }: { respond: (ok: boolean, payload: any) => void }) => {
      respond(true, {
        surface: latestSurface,
      });
    }
  );
}
