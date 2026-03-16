# Chat Streaming Tool Call Fixes

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix tool call ordering, duplicate entries, and history-vs-streaming mismatch in the Flutter chat interface by extracting event processing into a testable class, writing tests with real streaming event fixtures captured from tender-claw, and verifying against the live cluster.

**Architecture:** Extract the event-processing logic from the 2175-line `chat_stream.dart` widget into a pure Dart `ChatStreamProcessor` class. This separates state mutation from rendering, enabling unit tests with real WebSocket event sequences. Fixtures are captured from **live streaming events** (not derived from transcripts) via a Dart CLI capture tool that connects to tender-claw, sends chat messages, and records the exact `chat`/`agent` event sequence the client receives. Tests verify both streaming and history paths independently, plus parity between them.

**Tech Stack:** Flutter/Dart, Riverpod, flutter_test, web_socket_channel, OpenClaw WebSocket Protocol v3

---

## Critical Distinction: Transcript vs Chat Stream

| | JSONL Transcript (on disk) | Chat Stream (WebSocket events) |
|---|---|---|
| **Format** | Complete messages with interleaved `text` + `toolCall` content blocks in a single assistant entry | Separate `chat` events (text deltas/finals) and `agent` events (tool_call start/end, lifecycle) arriving in real-time |
| **Text + tools in one turn** | Single assistant `message` entry: `content: [{text}, {toolCall}, {text}, {toolCall}]` | Multiple events: `chat` delta (pre-tool text), then N `agent` tool_call starts, then N `agent` tool_call ends, then `chat` delta (post-tool text) |
| **Tool results** | Separate `message` with `role: "toolResult"` | `agent` event with `stream: "tool"` + `phase: "end"` or `stream: "tool_result"` |
| **Timing** | Post-hoc, complete | Real-time, partial/accumulating |

**The bugs manifest in the streaming path** -- that's what the user sees during a live chat. History load (from `chat.history` which returns transcript-style data) must produce the same visual result. We test both independently and verify parity.

---

## Root Cause Analysis

### Bug 1: Tool Cards in Wrong Order

During streaming, the event sequence for text + tools is:
```
1. chat delta (pre-tool text: "Hey! Let me check...")     -> creates assistant entry at index N
2. agent tool_call start (read:0)                         -> appends tool entry at index N+1
3. agent tool_call start (read:1)                         -> appends tool entry at index N+2
4. agent tool_call end (read:0, result)                   -> updates entry at N+1
5. agent tool_call end (read:1, result)                   -> updates entry at N+2
6. chat delta (post-tool text: "Here's what I found...")   -> BUG: updates entry at index N (before tool cards!)
```

Step 6 finds the existing streaming assistant entry (at index N) and updates it in-place (`chat_stream.dart:652-655`). But that entry is **before** the tool cards (N+1, N+2). The post-tool text should appear **after** the tool cards.

**Fix:** Track `_toolCardsInsertedSinceLastAssistant`. When a new `chat` delta arrives and tool cards have been inserted since the last assistant text, create a **new** assistant entry after the tool cards.

### Bug 2: Duplicate Entries

`chat_stream.dart:762-778` always appends a new `ChatEntry(role: 'tool')` for any `agent` event with `stream == 'tool_call' || stream == 'tool'` where `phase != 'end' && phase != 'result'`. No dedup check:

1. Gateway sends `stream: "tool_call"` (legacy) AND `stream: "tool"` (current) for same call -> 2 entries
2. Gateway sends progress events after start for same `toolCallId` -> additional entries

**Fix:** Before appending a tool entry, check if `entries` already contains one with the same `toolCallId`.

### Bug 3: History vs Streaming Mismatch

`_extractContent()` (`chat_stream.dart:341-354`) joins ALL text blocks from assistant messages, including whitespace `" "` spacers between `toolCall` blocks. This produces `"Hey!...\n \n "` for history-loaded entries, while streaming produces clean `"Hey!..."`.

Also, history creates entries in transcript order (assistant with all text, then toolResults), while streaming creates them in event order (assistant text, tool starts, tool ends, assistant text). Different visual sequences.

**Fix:** Parse assistant content blocks structure-aware in `loadHistory()`:
- Extract only pre-toolCall text (before first `toolCall` block)
- Skip whitespace spacers between tool calls
- Match the ordering that streaming produces

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| **Create** | `app/frontend/tool/capture_events.dart` | CLI tool: connects to OpenClaw WS, sends chat, records events as Dart fixture files |
| **Create** | `app/frontend/lib/features/chat/chat_stream_processor.dart` | Pure Dart event processor: `processEvent(WsEvent)`, `loadHistory(List)` -> `List<ChatEntry>` |
| **Create** | `app/frontend/test/features/chat/chat_stream_processor_test.dart` | Unit tests: streaming path, history path, parity |
| **Create** | `app/frontend/test/features/chat/fixtures/simple_greeting.dart` | Fixture: text-only response (from live capture) |
| **Create** | `app/frontend/test/features/chat/fixtures/text_then_tools.dart` | Fixture: text + parallel tool calls + final text (from live capture) |
| **Create** | `app/frontend/test/features/chat/fixtures/tools_only.dart` | Fixture: tool-call-only turn, no visible text (from live capture) |
| **Create** | `app/frontend/test/features/chat/fixtures/parallel_tools.dart` | Fixture: 3+ concurrent reads, out-of-order results (from live capture) |
| **Modify** | `app/frontend/lib/features/chat/chat_stream.dart` | Delegate to ChatStreamProcessor; keep only widget/render code |
| **Keep** | `app/frontend/test/features/chat/chat_entry_test.dart` | Existing tests must still pass |

---

## Chunk 1: Capture Tool + Fixtures

### Task 1: Build Dart CLI event capture tool

**Files:**
- Create: `app/frontend/tool/capture_events.dart`

This is a standalone Dart script (run with `dart run tool/capture_events.dart`) that:
1. Connects to an OpenClaw gateway via WebSocket (using `web_socket_channel` IOWebSocketChannel)
2. Completes the challenge-response handshake (same as `GatewayClient`)
3. Sends a `chat.send` request with a configurable message
4. Records ALL `chat` and `agent` events in order, with timestamps
5. Also sends a `chat.history` request after the run completes to capture the history format
6. Outputs both as a Dart fixture file (ready to copy into `test/features/chat/fixtures/`)

The capture tool connects to tender-claw via kubectl port-forward or direct cluster URL.

- [ ] **Step 1: Create `tool/capture_events.dart` with WebSocket connection + handshake**

The script uses `IOWebSocketChannel.connect()` and implements the challenge-response:
- Parse `connect.challenge` event, extract nonce
- Send `connect` request with `caps: ["tool-events"]`, auth token, operator role
- Wait for `hello-ok` response

Command-line args: `--url ws://... --token <gateway-token> --message "read MEMORY.md" --session main`

- [ ] **Step 2: Add chat.send and event recording**

After handshake:
- Send `chat.send` with the message and session key
- Record all received `WsEvent` objects (where `event == 'chat' || event == 'agent'`) into a list
- Stop recording when `agent` lifecycle `phase: "end"` is received
- Timeout after 60s

- [ ] **Step 3: Add chat.history capture**

After the run completes:
- Send `chat.history` with limit:10
- Extract the `messages` array from the response
- Record as the history fixture

- [ ] **Step 4: Add fixture output generation**

Output a Dart file with:
```dart
// AUTO-GENERATED by tool/capture_events.dart
// Captured from: <url> at <timestamp>
// Message: "<message>"
import 'package:trinity_shell/models/ws_frame.dart';

final historyMessages = <Map<String, dynamic>>[...];
final streamingEvents = <WsEvent>[...];
```

- [ ] **Step 5: Test the capture tool against tender-claw**

```bash
# Port-forward to tender-claw
kubectl port-forward deploy/openclaw-tender-claw -n trinity 18789:18789 &

# Run capture for simple greeting
dart run tool/capture_events.dart \
  --url ws://localhost:18789 \
  --token <token> \
  --message "hello, what time is it?" \
  --output test/features/chat/fixtures/simple_greeting.dart

# Run capture for tool calls
dart run tool/capture_events.dart \
  --url ws://localhost:18789 \
  --token <token> \
  --message "read my MEMORY.md file" \
  --output test/features/chat/fixtures/text_then_tools.dart
```

Verify output files are valid Dart with proper WsEvent construction.

- [ ] **Step 6: Commit**

```bash
git add app/frontend/tool/capture_events.dart
git commit -m "tool: add Dart CLI for capturing live WebSocket streaming events"
```

### Task 2: Capture fixtures from tender-claw

**Files:**
- Create: `app/frontend/test/features/chat/fixtures/simple_greeting.dart`
- Create: `app/frontend/test/features/chat/fixtures/text_then_tools.dart`
- Create: `app/frontend/test/features/chat/fixtures/tools_only.dart`
- Create: `app/frontend/test/features/chat/fixtures/parallel_tools.dart`

Each fixture contains BOTH:
- `historyMessages`: from `chat.history` response (the transcript-derived format)
- `streamingEvents`: from live WebSocket capture (the actual streaming event sequence)
- `expectedEntries`: the expected `ChatEntry` list (ground truth for both paths)

- [ ] **Step 1: Capture `simple_greeting` fixture**

Send a message that triggers NO tool calls (e.g., "hello, just a greeting"). Expected:
- Streaming: lifecycle start -> chat delta(s) -> chat final -> lifecycle end
- History: user msg + assistant msg (text-only)
- Expected entries: `[user, assistant]`

- [ ] **Step 2: Capture `text_then_tools` fixture**

Send a message that triggers text + tool calls (e.g., "read my MEMORY.md and USER.md files"). Expected:
- Streaming: lifecycle start -> chat delta("Let me read...") -> agent tool start(read:0) -> agent tool start(read:1) -> agent tool end(read:0) -> agent tool end(read:1) -> chat delta("Here's what I found...") -> chat final -> lifecycle end
- History: user, assistant(interleaved text+toolCalls), toolResult:0, toolResult:1, assistant(final text)
- Expected entries: `[user, assistant("Let me read..."), tool(read:0), tool(read:1), assistant("Here's what I found...")]`

- [ ] **Step 3: Capture `tools_only` fixture**

Send a message that triggers ONLY tool calls with no pre-tool text (e.g., the session startup sequence where assistant immediately calls tools). Expected:
- Streaming: lifecycle start -> agent tool start(s) -> agent tool end(s) -> chat delta/final -> lifecycle end
- The initial assistant message has only toolCall blocks, no pre-tool text
- Expected entries: `[user, tool(read:0), tool(read:1), ..., assistant("final response")]` (no empty assistant entry)

- [ ] **Step 4: Capture `parallel_tools` fixture**

Send a message that triggers 3+ parallel tool calls where results arrive out of order. Expected:
- Tool starts: read:0, read:1, read:2
- Tool ends: read:2 (completes first), read:0, read:1
- Verify `toolCallId` matching works correctly

- [ ] **Step 5: Clean up captured fixtures**

Review generated Dart files:
- Remove any sensitive data (file contents, paths) -- replace with representative but safe content
- Ensure all `WsEvent.fromJson()` calls are valid
- Add comments explaining the scenario
- Add the `expectedEntries` list (manually defined based on what correct rendering should look like)

- [ ] **Step 6: Commit**

```bash
git add app/frontend/test/features/chat/fixtures/
git commit -m "test: add captured streaming event fixtures from tender-claw"
```

---

## Chunk 2: Extract Processor + Write Tests

### Task 3: Create `ChatStreamProcessor` class

**Files:**
- Create: `app/frontend/lib/features/chat/chat_stream_processor.dart`

- [ ] **Step 1: Create processor file with class skeleton**

```dart
import 'dart:convert';
import '../../models/ws_frame.dart';
import 'chat_stream.dart' show ChatEntry;

/// Pure-logic event processor for chat streaming.
/// No Flutter dependency -- fully unit-testable.
class ChatStreamProcessor {
  static const int maxEntries = 500;

  final List<ChatEntry> entries = [];
  bool agentThinking = false;

  // Turn tracking
  bool _toolCardsInsertedSinceLastAssistant = false;
  final Set<String> _seenToolCallIds = {};

  // Optimistic echo
  final List<_PendingUserEcho> _pendingUserEchoes = [];

  // Stream key tracking
  int? _currentRunFirstAssistantSeq;
  bool currentRunHadToolGap = false;

  // A2UI
  String? lastCanvasSurface;
  final List<Map<String, dynamic>> pendingA2UIEvents = [];

  /// Process a single WsEvent. Returns true if entries changed.
  bool processEvent(WsEvent event) { ... }

  /// Load entries from a chat.history response.
  void loadHistory(List<dynamic> messages) { ... }

  /// Clear all state.
  void clear() { ... }
}
```

No Flutter imports. Only `dart:convert` and `ws_frame.dart`.

- [ ] **Step 2: Move `processEvent()` logic from `_handleChatEventInner`**

Copy event handling from `chat_stream.dart:552-799`. Remove `setState` wrappers. Key sections:
- Chat event handling (user echo, deltas, finals)
- Agent event handling (lifecycle, tool_call, tool_result)
- Optimistic echo dedup
- Stream key matching

- [ ] **Step 3: Move `loadHistory()` logic from `_loadHistory`**

Copy history parsing from `chat_stream.dart:273-323`. Include all helpers.

- [ ] **Step 4: Move all helper methods**

- `_assistantStreamKey()`, `_findAssistantIndexByStreamKey()`
- `_updateLastToolEntry()`
- `_recordOptimisticUser()`, `_consumeOptimisticUser()`
- `extractContent()` (make public static), `extractImageAttachments()`, `extractMediaArtifacts()`
- `extractA2UIText()`, `_capEntries()`

- [ ] **Step 5: Verify existing tests still pass**

Run: `cd app/frontend && flutter test test/features/chat/chat_entry_test.dart -v`
Expected: All PASS

- [ ] **Step 6: Commit**

```bash
git add app/frontend/lib/features/chat/chat_stream_processor.dart
git commit -m "refactor: extract ChatStreamProcessor from chat_stream.dart"
```

### Task 4: Write comprehensive processor tests (initially failing)

**Files:**
- Create: `app/frontend/test/features/chat/chat_stream_processor_test.dart`

- [ ] **Step 1: Write streaming path tests**

```dart
group('Streaming path (processEvent)', () {
  test('simple greeting: lifecycle -> deltas -> final -> lifecycle end', () {
    final p = ChatStreamProcessor();
    for (final e in simpleGreeting.streamingEvents) p.processEvent(e);
    expect(p.entries.length, 2);
    expect(p.entries[0].role, 'user');
    expect(p.entries[1].role, 'assistant');
    expect(p.entries[1].isStreaming, false);
    expect(p.entries[1].content, simpleGreeting.expectedEntries[1]['content']);
  });

  test('text-then-tools: correct order [user, assistant, tool, tool, assistant]', () {
    final p = ChatStreamProcessor();
    for (final e in textThenTools.streamingEvents) p.processEvent(e);
    expect(p.entries.map((e) => e.role).toList(),
      ['user', 'assistant', 'tool', 'tool', 'assistant']);
    // Pre-tool text should be clean
    expect(p.entries[1].content, textThenTools.expectedEntries[1]['content']);
    // Post-tool text should be AFTER tool cards
    expect(p.entries[4].content, textThenTools.expectedEntries[4]['content']);
  });

  test('text-then-tools: no duplicate tool entries', () {
    final p = ChatStreamProcessor();
    for (final e in textThenTools.streamingEvents) p.processEvent(e);
    final toolEntries = p.entries.where((e) => e.role == 'tool').toList();
    final ids = toolEntries.map((e) => e.toolCallId).toSet();
    expect(ids.length, toolEntries.length, reason: 'no duplicate toolCallIds');
  });

  test('tools-only: no empty assistant entry', () {
    final p = ChatStreamProcessor();
    for (final e in toolsOnly.streamingEvents) p.processEvent(e);
    final emptyAssistants = p.entries.where((e) =>
      e.role == 'assistant' && e.content.trim().isEmpty);
    expect(emptyAssistants, isEmpty);
  });

  test('parallel-tools: out-of-order results matched to correct entries', () {
    final p = ChatStreamProcessor();
    for (final e in parallelTools.streamingEvents) p.processEvent(e);
    final toolEntries = p.entries.where((e) => e.role == 'tool').toList();
    for (final te in toolEntries) {
      expect(te.isStreaming, false, reason: '${te.toolCallId} should be completed');
      expect(te.content, isNotEmpty, reason: '${te.toolCallId} should have result');
    }
  });
});
```

- [ ] **Step 2: Write history path tests**

```dart
group('History path (loadHistory)', () {
  test('simple greeting: produces [user, assistant]', () {
    final p = ChatStreamProcessor();
    p.loadHistory(simpleGreeting.historyMessages);
    expect(p.entries.length, 2);
    expect(p.entries.map((e) => e.role).toList(), ['user', 'assistant']);
  });

  test('text-then-tools: correct order, clean pre-tool text', () {
    final p = ChatStreamProcessor();
    p.loadHistory(textThenTools.historyMessages);
    expect(p.entries.map((e) => e.role).toList(),
      ['user', 'assistant', 'tool', 'tool', 'assistant']);
    // Pre-tool text should not have whitespace spacers
    final preToolText = p.entries[1].content;
    expect(preToolText.trim(), preToolText, reason: 'no trailing whitespace');
    expect(preToolText, isNot(contains('\n \n')), reason: 'no spacer artifacts');
  });

  test('tools-only: no empty assistant entry', () {
    final p = ChatStreamProcessor();
    p.loadHistory(toolsOnly.historyMessages);
    final emptyAssistants = p.entries.where((e) =>
      e.role == 'assistant' && e.content.trim().isEmpty);
    expect(emptyAssistants, isEmpty);
  });
});
```

- [ ] **Step 3: Write parity tests (streaming == history)**

```dart
group('Parity (streaming == history)', () {
  for (final name in ['simple_greeting', 'text_then_tools', 'tools_only', 'parallel_tools']) {
    test('$name: streaming and history produce same entry structure', () {
      final fixture = fixtureByName(name);

      final sp = ChatStreamProcessor();
      for (final e in fixture.streamingEvents) sp.processEvent(e);

      final hp = ChatStreamProcessor();
      hp.loadHistory(fixture.historyMessages);

      expect(sp.entries.length, hp.entries.length,
        reason: 'same number of entries');
      for (int i = 0; i < sp.entries.length; i++) {
        expect(sp.entries[i].role, hp.entries[i].role,
          reason: 'entry $i role matches');
        // Content comparison: trim both since streaming may have slight whitespace differences
        expect(sp.entries[i].content.trim(), hp.entries[i].content.trim(),
          reason: 'entry $i content matches');
        expect(sp.entries[i].toolName, hp.entries[i].toolName,
          reason: 'entry $i toolName matches');
      }
    });
  }
});
```

- [ ] **Step 4: Write expected-output tests**

```dart
group('Expected output (ground truth)', () {
  for (final name in ['simple_greeting', 'text_then_tools', 'tools_only', 'parallel_tools']) {
    test('$name: streaming matches expected entries', () {
      final fixture = fixtureByName(name);
      final p = ChatStreamProcessor();
      for (final e in fixture.streamingEvents) p.processEvent(e);

      expect(p.entries.length, fixture.expectedEntries.length);
      for (int i = 0; i < p.entries.length; i++) {
        expect(p.entries[i].role, fixture.expectedEntries[i]['role']);
        if (fixture.expectedEntries[i].containsKey('content')) {
          expect(p.entries[i].content, fixture.expectedEntries[i]['content']);
        }
      }
    });

    test('$name: history matches expected entries', () {
      final fixture = fixtureByName(name);
      final p = ChatStreamProcessor();
      p.loadHistory(fixture.historyMessages);

      expect(p.entries.length, fixture.expectedEntries.length);
      for (int i = 0; i < p.entries.length; i++) {
        expect(p.entries[i].role, fixture.expectedEntries[i]['role']);
      }
    });
  }
});
```

- [ ] **Step 5: Run tests to verify they fail**

Run: `cd app/frontend && flutter test test/features/chat/chat_stream_processor_test.dart -v`
Expected: FAIL (processor has existing bugs)

- [ ] **Step 6: Commit**

```bash
git add app/frontend/test/features/chat/chat_stream_processor_test.dart
git commit -m "test: add comprehensive streaming/history/parity tests (failing)"
```

---

## Chunk 3: Fix the Three Bugs

### Task 5: Fix duplicate tool entries (Bug 2)

**Files:**
- Modify: `app/frontend/lib/features/chat/chat_stream_processor.dart`

- [ ] **Step 1: Add dedup check in tool_call start handling**

In `processEvent()`, in the `stream == 'tool_call' || stream == 'tool'` branch, before appending:

```dart
if (toolCallId != null && toolCallId.isNotEmpty) {
  if (_seenToolCallIds.contains(toolCallId)) return true; // already tracked
  _seenToolCallIds.add(toolCallId);
}
```

Clear `_seenToolCallIds` on `lifecycle:start`.

- [ ] **Step 2: Run dedup tests**

Run: `cd app/frontend && flutter test test/features/chat/chat_stream_processor_test.dart --name 'no duplicate' -v`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add app/frontend/lib/features/chat/chat_stream_processor.dart
git commit -m "fix: prevent duplicate tool cards for same toolCallId"
```

### Task 6: Fix tool card ordering (Bug 1)

**Files:**
- Modify: `app/frontend/lib/features/chat/chat_stream_processor.dart`

- [ ] **Step 1: Add turn-boundary tracking and new-entry-after-tools logic**

When a tool entry is appended:
```dart
_toolCardsInsertedSinceLastAssistant = true;
```

In the `chat` delta handling, when `_toolCardsInsertedSinceLastAssistant && text.isNotEmpty`:
```dart
// Tool cards were inserted after previous assistant text.
// Create a NEW assistant entry after the tool cards.
entries.add(ChatEntry(
  role: 'assistant',
  content: text,
  isStreaming: true,
  metadata: assistantStreamKey == null ? null : {'_streamKey': assistantStreamKey},
));
_toolCardsInsertedSinceLastAssistant = false;
```

Otherwise, use the existing find-and-update logic.

On `lifecycle:end` and `lifecycle:start`, reset `_toolCardsInsertedSinceLastAssistant = false`.

- [ ] **Step 2: Run ordering tests**

Run: `cd app/frontend && flutter test test/features/chat/chat_stream_processor_test.dart --name 'correct order' -v`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add app/frontend/lib/features/chat/chat_stream_processor.dart
git commit -m "fix: create new assistant entry after tool cards for correct ordering"
```

### Task 7: Fix history vs streaming parity (Bug 3)

**Files:**
- Modify: `app/frontend/lib/features/chat/chat_stream_processor.dart`

- [ ] **Step 1: Rewrite `loadHistory()` to handle interleaved content blocks**

For assistant messages with `content` as `List`:

```dart
if (role == 'assistant') {
  final contentList = msg['content'];
  if (contentList is List) {
    String preToolText = '';
    bool hitToolCall = false;

    for (final block in contentList) {
      if (block is! Map<String, dynamic>) continue;
      final type = block['type'] as String?;
      if (type == 'thinking') continue; // skip thinking blocks
      if (type == 'toolCall') {
        hitToolCall = true;
        continue; // tool calls come as separate toolResult messages
      }
      if (type == 'text' && !hitToolCall) {
        preToolText += block['text'] as String? ?? '';
      }
      // Text blocks AFTER toolCall are whitespace spacers -- skip them
    }

    preToolText = preToolText.trim();
    if (preToolText.isNotEmpty) {
      entries.add(ChatEntry(role: 'assistant', content: preToolText, ...));
    }
    // If no toolCall blocks were hit, this is a pure text response --
    // join all text blocks normally
    if (!hitToolCall) {
      final allText = extractContent(contentList);
      if (allText.isNotEmpty) {
        entries.add(ChatEntry(role: 'assistant', content: allText, ...));
      }
    }
  }
}
```

Wait -- there's a subtlety: if there are NO toolCall blocks, we should use the normal `extractContent()` path. Only when toolCall blocks are present do we need the structure-aware parsing.

Also, the second assistant message (post-tool text) comes as a separate message in the transcript with only text blocks (no toolCalls). The existing code handles this correctly already -- it creates a normal assistant entry. We just need to make sure we DON'T create one for the interleaved-toolCall messages when the pre-tool text is empty (the tools-only case).

- [ ] **Step 2: Run parity tests**

Run: `cd app/frontend && flutter test test/features/chat/chat_stream_processor_test.dart --name 'parity' -v`
Expected: ALL PASS

- [ ] **Step 3: Run ALL processor tests**

Run: `cd app/frontend && flutter test test/features/chat/chat_stream_processor_test.dart -v`
Expected: ALL PASS

- [ ] **Step 4: Commit**

```bash
git add app/frontend/lib/features/chat/chat_stream_processor.dart
git commit -m "fix: structure-aware history parsing for streaming parity"
```

---

## Chunk 4: Wire Into Widget + Build + Deploy

### Task 8: Wire ChatStreamProcessor into ChatStreamView

**Files:**
- Modify: `app/frontend/lib/features/chat/chat_stream.dart`

- [ ] **Step 1: Add processor field**

```dart
final _processor = ChatStreamProcessor();
```

- [ ] **Step 2: Delegate event handling to processor**

Replace `_handleChatEventInner(event)` body with:
```dart
final changed = _processor.processEvent(event);
// Handle A2UI events emitted by processor
for (final a2ui in _processor.pendingA2UIEvents) {
  _handleA2UIToolResult(a2ui);
}
_processor.pendingA2UIEvents.clear();
if (changed) setState(() {});
```

- [ ] **Step 3: Delegate history loading to processor**

Replace inline history parsing in `_loadHistory()` with:
```dart
_processor.loadHistory(messages);
_lastCanvasSurface = _processor.lastCanvasSurface;
```

- [ ] **Step 4: Replace `_entries` with `_processor.entries`**

Search-and-replace throughout the widget. Also replace `_agentThinking` with `_processor.agentThinking`.

- [ ] **Step 5: Remove methods that moved to processor**

Delete duplicated helper methods from `chat_stream.dart`. Keep only:
- Widget classes (`ChatStreamView`, `_UserBubble`, `_AssistantBubble`, `_ToolCard`, etc.)
- `ChatEntry` class (shared)
- Widget-specific methods (scroll, build, layout)
- A2UI rendering (calls into canvas, needs widget context)

- [ ] **Step 6: Run all tests**

Run: `cd app/frontend && flutter test -v`
Expected: ALL PASS

- [ ] **Step 7: Commit**

```bash
git add app/frontend/lib/features/chat/chat_stream.dart
git commit -m "refactor: wire ChatStreamProcessor into ChatStreamView"
```

### Task 9: Build and deploy to verify against tender-claw

- [ ] **Step 1: Rebuild frontend**

```bash
docker compose -f app/docker-compose.yml --profile build build --no-cache frontend-builder
docker compose -f app/docker-compose.yml --profile build run --rm frontend-builder
docker restart trinity-nginx
```

- [ ] **Step 2: Verify against tender-claw (manual testing)**

Open Flutter shell in browser, connect to tender-claw. Test these scenarios:

| Scenario | Send | Expected |
|----------|------|----------|
| Simple greeting | "hi there" | User bubble -> thinking indicator -> assistant bubble. No tool cards. |
| Text + tools | "read my MEMORY.md file" | User -> assistant("Let me read...") -> tool(read) with streaming dots -> tool result -> assistant("Here's what I found...") |
| Parallel tools | "read MEMORY.md, USER.md, and SOUL.md" | User -> assistant(pre-text) -> 3 tool cards (all streaming) -> results fill in -> assistant(final text) |
| Tools only | (trigger session startup) | Tool cards appear directly, no empty assistant bubble |
| Page refresh | Refresh browser | History renders identically to what streaming showed |

- [ ] **Step 3: Test edge cases**

- Abort mid-stream (click stop button) -- no orphaned streaming entries
- Switch sessions while streaming -- clean state transition
- Rapid messages -- optimistic echo dedup works
- Long tool result -- expand/collapse still works

- [ ] **Step 4: Commit any adjustments**

```bash
git add -A
git commit -m "fix: edge case adjustments from live verification"
```

---

## Risk Notes

1. **Capture tool depends on cluster access**: If tender-claw is unreachable, fall back to manually constructing fixtures based on the documented protocol format. The protocol docs and the TS/Dart client code give us the exact event shapes.

2. **Gateway version differences**: tender-claw runs 2026.3.11, local Docker runs whatever's cached. Event format may differ slightly (e.g., `stream: "tool"` vs `stream: "tool_call"`). The processor should handle both -- the existing code already does this.

3. **Content of captured fixtures**: Tool results from real sessions may contain sensitive content (file contents, paths). Sanitize fixtures after capture -- replace with representative but safe placeholder content.

4. **A2UI handling**: The processor collects A2UI events in `pendingA2UIEvents` for the widget to handle. This is needed because A2UI rendering requires widget context (emitting to canvas streams). The processor stays pure.
