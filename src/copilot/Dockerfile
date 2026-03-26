FROM node:20-bookworm-slim

WORKDIR /app
ENV PATH="/app/node_modules/.bin:${PATH}"

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ripgrep ca-certificates bash curl \
    && curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/$(dpkg --print-architecture)/kubectl" \
    && chmod +x kubectl && mv kubectl /usr/local/bin/ \
    && rm -rf /var/lib/apt/lists/*

COPY src/copilot/package.json src/copilot/package-lock.json* ./
RUN npm ci --omit=dev

COPY src/copilot/src ./src

RUN mkdir -p /workspace/.opencode/tools /workspace/.opencode/skills
COPY opencode.jsonc /workspace/opencode.jsonc
COPY opencode.jsonc /workspace/opencode.json
COPY src/copilot/AGENT.md /workspace/AGENT.md
COPY src/copilot/AGENT.md /workspace/AGENTS.md
COPY src/copilot/tools/ /workspace/.opencode/tools/
COPY .opencode/skills/ /workspace/.opencode/skills/

ENV COPILOT_WORKSPACE=/workspace
ENV COPILOT_PORT=18802
ENV OPENCODE_PORT=4096

EXPOSE 18802

CMD ["node", "src/index.js"]
