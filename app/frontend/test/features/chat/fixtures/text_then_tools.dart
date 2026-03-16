/// Fixture: assistant text + parallel tool calls + final text.
/// Based on tender-claw session 6d7310c9, message a6282eff.
///
/// Flow: user greets -> assistant says "Hey! Let me catch up..." ->
///       3 parallel read tool calls -> tool results -> assistant final text.
///
/// This is the most common pattern and the source of all three bugs
/// (wrong order, duplicates, history/streaming mismatch).
import 'package:trinity_shell/models/ws_frame.dart';

const _userText = 'hi again, long time no see.';
const _preToolText =
    "Hey! Good to see you again. Let me catch up on what's been happening...";
const _postToolText =
    "Hey! Good to see you again.\n\nLooking at the memory files, "
    "it seems like it's been a quiet few days here. "
    "What's on your mind today?";
const _tool0Result = 'ENOENT: no such file or directory';
const _tool1Result = 'ENOENT: no such file or directory';
const _tool2Result = '# Trinity Workspace Memory\n\nDeployment info here...';

/// What chat.history returns: assistant message with interleaved text+toolCall blocks.
final historyMessages = <Map<String, dynamic>>[
  {
    'role': 'user',
    'content': _userText,
    'timestamp': 1773661024351,
  },
  // Assistant message with interleaved content: text, toolCall, text, toolCall, text, toolCall, text
  {
    'role': 'assistant',
    'content': [
      {'type': 'thinking', 'text': 'Let me check the memory files...'},
      {'type': 'text', 'text': _preToolText},
      {
        'type': 'toolCall',
        'id': 'functions.read:0',
        'name': 'read',
        'arguments': {
          'file_path': '/home/node/.openclaw/workspace/memory/2026-03-16.md'
        },
      },
      {'type': 'text', 'text': ' '},
      {
        'type': 'toolCall',
        'id': 'functions.read:1',
        'name': 'read',
        'arguments': {
          'file_path': '/home/node/.openclaw/workspace/memory/2026-03-15.md'
        },
      },
      {'type': 'text', 'text': ' '},
      {
        'type': 'toolCall',
        'id': 'functions.read:2',
        'name': 'read',
        'arguments': {
          'file_path': '/home/node/.openclaw/workspace/MEMORY.md'
        },
      },
      {'type': 'text', 'text': ' '},
    ],
    'id': 'a6282eff',
    'timestamp': 1773661029164,
  },
  // Tool results as separate messages
  {
    'role': 'toolResult',
    'toolCallId': 'functions.read:0',
    'toolName': 'read',
    'content': [
      {'type': 'text', 'text': _tool0Result},
    ],
    'args': '{"file_path":"/home/node/.openclaw/workspace/memory/2026-03-16.md"}',
    'timestamp': 1773661029179,
  },
  {
    'role': 'toolResult',
    'toolCallId': 'functions.read:1',
    'toolName': 'read',
    'content': [
      {'type': 'text', 'text': _tool1Result},
    ],
    'args': '{"file_path":"/home/node/.openclaw/workspace/memory/2026-03-15.md"}',
    'timestamp': 1773661029190,
  },
  {
    'role': 'toolResult',
    'toolCallId': 'functions.read:2',
    'toolName': 'read',
    'content': [
      {'type': 'text', 'text': _tool2Result},
    ],
    'args': '{"file_path":"/home/node/.openclaw/workspace/MEMORY.md"}',
    'timestamp': 1773661029196,
  },
  // Final assistant text (separate message in transcript)
  {
    'role': 'assistant',
    'content': [
      {'type': 'thinking', 'text': 'Looking at the results...'},
      {'type': 'text', 'text': _postToolText},
    ],
    'id': 'c09b195f',
    'timestamp': 1773661033843,
  },
];

/// Streaming events: the real-time WebSocket sequence.
final streamingEvents = <WsEvent>[
  // User local echo
  WsEvent.fromJson({
    'event': 'chat',
    'payload': {
      'type': 'message',
      'role': 'user',
      'content': _userText,
      'localEcho': true,
      'idempotencyKey': 'idem-tools-001',
    },
  }),
  // Lifecycle start
  WsEvent.fromJson({
    'event': 'agent',
    'payload': {
      'stream': 'lifecycle',
      'data': {'phase': 'start'},
    },
    'seq': 1,
  }),
  // Pre-tool text delta
  WsEvent.fromJson({
    'event': 'chat',
    'payload': {
      'state': 'delta',
      'message': {
        'id': 'a6282eff',
        'content': [
          {'type': 'text', 'text': _preToolText},
        ],
      },
      'runId': 'run-001',
    },
  }),
  // Tool call start: read:0
  WsEvent.fromJson({
    'event': 'agent',
    'payload': {
      'stream': 'tool',
      'data': {
        'phase': 'start',
        'tool': 'read',
        'name': 'read',
        'id': 'functions.read:0',
        'toolCallId': 'functions.read:0',
        'args': {
          'file_path': '/home/node/.openclaw/workspace/memory/2026-03-16.md'
        },
      },
    },
    'seq': 3,
  }),
  // Tool call start: read:1
  WsEvent.fromJson({
    'event': 'agent',
    'payload': {
      'stream': 'tool',
      'data': {
        'phase': 'start',
        'tool': 'read',
        'name': 'read',
        'id': 'functions.read:1',
        'toolCallId': 'functions.read:1',
        'args': {
          'file_path': '/home/node/.openclaw/workspace/memory/2026-03-15.md'
        },
      },
    },
    'seq': 4,
  }),
  // Tool call start: read:2
  WsEvent.fromJson({
    'event': 'agent',
    'payload': {
      'stream': 'tool',
      'data': {
        'phase': 'start',
        'tool': 'read',
        'name': 'read',
        'id': 'functions.read:2',
        'toolCallId': 'functions.read:2',
        'args': {
          'file_path': '/home/node/.openclaw/workspace/MEMORY.md'
        },
      },
    },
    'seq': 5,
  }),
  // Tool call end: read:0
  WsEvent.fromJson({
    'event': 'agent',
    'payload': {
      'stream': 'tool',
      'data': {
        'phase': 'end',
        'tool': 'read',
        'id': 'functions.read:0',
        'toolCallId': 'functions.read:0',
        'result': _tool0Result,
      },
    },
    'seq': 6,
  }),
  // Tool call end: read:1
  WsEvent.fromJson({
    'event': 'agent',
    'payload': {
      'stream': 'tool',
      'data': {
        'phase': 'end',
        'tool': 'read',
        'id': 'functions.read:1',
        'toolCallId': 'functions.read:1',
        'result': _tool1Result,
      },
    },
    'seq': 7,
  }),
  // Tool call end: read:2
  WsEvent.fromJson({
    'event': 'agent',
    'payload': {
      'stream': 'tool',
      'data': {
        'phase': 'end',
        'tool': 'read',
        'id': 'functions.read:2',
        'toolCallId': 'functions.read:2',
        'result': _tool2Result,
      },
    },
    'seq': 8,
  }),
  // Post-tool text delta (NEW assistant message after tools)
  WsEvent.fromJson({
    'event': 'chat',
    'payload': {
      'state': 'delta',
      'message': {
        'id': 'c09b195f',
        'content': [
          {'type': 'text', 'text': _postToolText},
        ],
      },
      'runId': 'run-001',
    },
  }),
  // Final
  WsEvent.fromJson({
    'event': 'chat',
    'payload': {
      'state': 'final',
      'message': {
        'id': 'c09b195f',
        'content': [
          {'type': 'text', 'text': _postToolText},
        ],
      },
      'runId': 'run-001',
    },
  }),
  // Lifecycle end
  WsEvent.fromJson({
    'event': 'agent',
    'payload': {
      'stream': 'lifecycle',
      'data': {'phase': 'end'},
    },
  }),
];

/// Expected entries: streaming and history should both produce this.
final expectedEntries = <Map<String, dynamic>>[
  {'role': 'user', 'content': _userText},
  {'role': 'assistant', 'content': _preToolText},
  {'role': 'tool', 'toolName': 'read', 'toolCallId': 'functions.read:0'},
  {'role': 'tool', 'toolName': 'read', 'toolCallId': 'functions.read:1'},
  {'role': 'tool', 'toolName': 'read', 'toolCallId': 'functions.read:2'},
  {'role': 'assistant', 'content': _postToolText},
];
