/// Fixture: tool-call-only turn (no visible pre-tool assistant text).
/// Based on tender-claw session 18a34872, message c96741bb.
///
/// Flow: user sends message -> assistant immediately calls tools
///       (no pre-tool text) -> tool results -> final assistant text.
///
/// Tests that empty assistant entries are not created.
import 'package:trinity_shell/models/ws_frame.dart';

const _userText = 'Execute startup sequence.';
const _tool0Result = '# SOUL.md\nBe genuinely helpful...';
const _tool1Result = '# USER.md\nEmpty template...';
const _finalText =
    'Hey there. I\'m up and running. What\'s on your mind today?';

/// History: assistant message has ONLY toolCall blocks (no pre-tool text).
final historyMessages = <Map<String, dynamic>>[
  {
    'role': 'user',
    'content': _userText,
    'timestamp': 1773378800634,
  },
  // Assistant message: thinking + toolCalls only, no user-visible text before tools
  {
    'role': 'assistant',
    'content': [
      {'type': 'thinking', 'text': 'Let me read the startup files...'},
      {
        'type': 'toolCall',
        'id': 'functions.read:0',
        'name': 'read',
        'arguments': {'file_path': '/home/node/.openclaw/workspace/SOUL.md'},
      },
      {'type': 'text', 'text': ' '},
      {
        'type': 'toolCall',
        'id': 'functions.read:1',
        'name': 'read',
        'arguments': {'file_path': '/home/node/.openclaw/workspace/USER.md'},
      },
      {'type': 'text', 'text': ' '},
    ],
    'id': 'c96741bb',
    'timestamp': 1773378803506,
  },
  {
    'role': 'toolResult',
    'toolCallId': 'functions.read:0',
    'toolName': 'read',
    'content': [
      {'type': 'text', 'text': _tool0Result},
    ],
    'args': '{"file_path":"/home/node/.openclaw/workspace/SOUL.md"}',
    'timestamp': 1773378803518,
  },
  {
    'role': 'toolResult',
    'toolCallId': 'functions.read:1',
    'toolName': 'read',
    'content': [
      {'type': 'text', 'text': _tool1Result},
    ],
    'args': '{"file_path":"/home/node/.openclaw/workspace/USER.md"}',
    'timestamp': 1773378803526,
  },
  // Final assistant text
  {
    'role': 'assistant',
    'content': [
      {'type': 'thinking', 'text': 'Now greet based on SOUL.md...'},
      {'type': 'text', 'text': _finalText},
    ],
    'id': '12b62dc7',
    'timestamp': 1773378826493,
  },
];

/// Streaming events: tools start immediately, no pre-tool text delta.
final streamingEvents = <WsEvent>[
  // User local echo
  WsEvent.fromJson({
    'event': 'chat',
    'payload': {
      'type': 'message',
      'role': 'user',
      'content': _userText,
      'localEcho': true,
      'idempotencyKey': 'idem-toolsonly-001',
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
  // Tool call start: read:0 (immediately, no text delta first)
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
        'args': {'file_path': '/home/node/.openclaw/workspace/SOUL.md'},
      },
    },
    'seq': 2,
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
        'args': {'file_path': '/home/node/.openclaw/workspace/USER.md'},
      },
    },
    'seq': 3,
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
    'seq': 4,
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
    'seq': 5,
  }),
  // Post-tool text delta
  WsEvent.fromJson({
    'event': 'chat',
    'payload': {
      'state': 'delta',
      'message': {
        'id': '12b62dc7',
        'content': [
          {'type': 'text', 'text': _finalText},
        ],
      },
    },
  }),
  // Final
  WsEvent.fromJson({
    'event': 'chat',
    'payload': {
      'state': 'final',
      'message': {
        'id': '12b62dc7',
        'content': [
          {'type': 'text', 'text': _finalText},
        ],
      },
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

/// Expected: no empty assistant entry. Tool cards appear directly after user.
final expectedEntries = <Map<String, dynamic>>[
  {'role': 'user', 'content': _userText},
  {'role': 'tool', 'toolName': 'read', 'toolCallId': 'functions.read:0'},
  {'role': 'tool', 'toolName': 'read', 'toolCallId': 'functions.read:1'},
  {'role': 'assistant', 'content': _finalText},
];
