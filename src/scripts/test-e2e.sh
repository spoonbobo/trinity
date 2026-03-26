#!/usr/bin/env bash
set -euo pipefail

GATEWAY_URL="${GATEWAY_URL:-ws://localhost:18789}"
GATEWAY_TOKEN="${GATEWAY_TOKEN:-replace-me-with-a-real-token}"
SHELL_URL="${SHELL_URL:-http://localhost}"

# Derive HTTP base URL from GATEWAY_URL (strip ws:// -> http://)
GATEWAY_HTTP_URL=$(echo "$GATEWAY_URL" | sed 's|^ws://|http://|; s|^wss://|https://|')

# Warn if using placeholder token
if [ "$GATEWAY_TOKEN" = "replace-me-with-a-real-token" ]; then
  echo "WARNING: GATEWAY_TOKEN is set to placeholder value. Set it in your environment."
fi

FAILURES=0

echo "=== Trinity AGI E2E Smoke Test ==="
echo ""

# 1. Check OpenClaw gateway is reachable
echo "[1/4] Checking OpenClaw Gateway..."
if curl -sf --connect-timeout 5 --max-time 10 "$GATEWAY_HTTP_URL/" > /dev/null 2>&1; then
  echo "  OK: Gateway is responding at $GATEWAY_HTTP_URL"
else
  echo "  FAIL: Gateway not reachable at $GATEWAY_HTTP_URL. Run: docker compose up -d"
  exit 1
fi

# 2. Check Flutter shell is served via nginx
echo "[2/4] Checking Flutter Shell (nginx)..."
if curl -sf --connect-timeout 5 --max-time 10 "$SHELL_URL" 2>/dev/null | grep -q "Trinity AGI"; then
  echo "  OK: Flutter shell is served at $SHELL_URL"
else
  echo "  WARN: Flutter shell may not be built yet."
  echo "  Run: docker compose --profile build run --rm frontend-builder"
  FAILURES=$((FAILURES + 1))
fi

# 3. Test OpenAI-compatible chat completions endpoint
echo "[3/4] Testing Chat Completions API..."
RESPONSE=$(curl -sf --connect-timeout 5 --max-time 30 "$GATEWAY_HTTP_URL/v1/chat/completions" \
  -H "Authorization: Bearer $GATEWAY_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"model":"openclaw","messages":[{"role":"user","content":"Say hello in exactly 3 words."}]}' \
  2>/dev/null || echo "FAIL")

if [ "$RESPONSE" != "FAIL" ] && echo "$RESPONSE" | grep -qv "FAIL"; then
  echo "  OK: Chat completions endpoint responded"
  echo "  Response: $(echo "$RESPONSE" | head -c 200)"
else
  echo "  WARN: Chat completions not available (may need provider API key)"
  FAILURES=$((FAILURES + 1))
fi

# 4. Test tools invoke endpoint
echo "[4/4] Testing Tools Invoke API..."
TOOLS_RESPONSE=$(curl -sf --connect-timeout 5 --max-time 10 "$GATEWAY_HTTP_URL/tools/invoke" \
  -H "Authorization: Bearer $GATEWAY_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"tool":"sessions_list","action":"json","args":{}}' \
  2>/dev/null || echo "FAIL")

if [ "$TOOLS_RESPONSE" != "FAIL" ] && echo "$TOOLS_RESPONSE" | grep -qv "FAIL"; then
  echo "  OK: Tools invoke endpoint responded"
else
  echo "  WARN: Tools invoke not available"
  FAILURES=$((FAILURES + 1))
fi

echo ""
if [ "$FAILURES" -gt 0 ]; then
  echo "=== E2E Test Complete: $FAILURES warning(s) ==="
  exit 1
else
  echo "=== E2E Test Complete: All checks passed ==="
  exit 0
fi
