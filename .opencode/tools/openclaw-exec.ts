import { tool } from "@opencode-ai/plugin"

export default tool({
  description:
    "Run an OpenClaw CLI command inside the trinity-openclaw Docker container. " +
    "Examples: 'status', 'models', 'sessions list', 'health --token $TOK', 'doctor --fix'.",
  args: {
    command: tool.schema
      .string()
      .describe(
        "The openclaw subcommand and arguments, e.g. 'status' or 'sessions list'"
      ),
  },
  async execute(args) {
    const parts = args.command.split(/\s+/)
    const result =
      await Bun.$`docker exec trinity-openclaw openclaw ${parts}`.text()
    return result.trim()
  },
})
