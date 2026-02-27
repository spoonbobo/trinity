#!/bin/bash
set -euo pipefail

GATEWAY_URL="${GATEWAY_URL:-ws://localhost:18789}"
GATEWAY_TOKEN="${GATEWAY_TOKEN:-replace-me-with-a-real-token}"
SHELL_URL="${SHELL_URL:-http://localhost}"

echo "=== Trinity AGI E2E Smoke Test ==="
echo ""

# 1. Check OpenClaw gateway is reachable
echo "[1/4] Checking OpenClaw Gateway..."
if curl -sf "http://localhost:18789/" > /dev/null 2>&1; then
  echo "  OK: Gateway is responding on :18789"
else
  echo "  FAIL: Gateway not reachable. Run: docker compose up -d"
  exit 1
fi

# 2. Check Flutter shell is served via nginx
echo "[2/4] Checking Flutter Shell (nginx)..."
if curl -sf "$SHELL_URL" | grep -q "Trinity AGI" 2>/dev/null; then
  echo "  OK: Flutter shell is served on :80"
else
  echo "  WARN: Flutter shell may not be built yet."
  echo "  Run: docker compose --profile build run --rm frontend-builder"
fi

# 3. Test OpenAI-compatible chat completions endpoint
echo "[3/4] Testing Chat Completions API..."
RESPONSE=$(curl -sf "http://localhost:18789/v1/chat/completions" \
  -H "Authorization: Bearer $GATEWAY_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"model":"openclaw","messages":[{"role":"user","content":"Say hello in exactly 3 words."}]}' \
  2>/dev/null || echo "FAIL")

if [ "$RESPONSE" != "FAIL" ]; then
  echo "  OK: Chat completions endpoint responded"
  echo "  Response: $(echo "$RESPONSE" | head -c 200)"
else
  echo "  WARN: Chat completions not available (may need provider API key)"
fi

# 4. Test tools invoke endpoint
echo "[4/4] Testing Tools Invoke API..."
TOOLS_RESPONSE=$(curl -sf "http://localhost:18789/tools/invoke" \
  -H "Authorization: Bearer $GATEWAY_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"tool":"sessions_list","action":"json","args":{}}' \
  2>/dev/null || echo "FAIL")

if [ "$TOOLS_RESPONSE" != "FAIL" ]; then
  echo "  OK: Tools invoke endpoint responded"
else
  echo "  WARN: Tools invoke not available"
fi

echo ""
echo "=== E2E Test Complete ==="
