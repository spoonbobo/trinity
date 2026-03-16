/// Fixture: parallel tool calls with out-of-order result delivery.
///
/// Flow: user asks to read 3 files -> assistant text -> 3 parallel reads start ->
///       results arrive out of order (read:2 first, then read:0, then read:1) ->
///       final assistant text.
///
/// Tests that toolCallId matching correctly routes results to the right entries.
import 'package:trinity_shell/models/ws_frame.dart';

const _userText = 'Read SOUL.md, USER.md, and MEMORY.md';
const _preToolText = 'Let me read those files for you...';
const _postToolText = 'Here are the contents of all three files.';
const _tool0Result = '# SOUL.md content';
const _tool1Result = '# USER.md content';
const _tool2Result = '# MEMORY.md content';

/// History format.
final historyMessages = <Map<String, dynamic>>[
  {
    'role': 'user',
    'content': _userText,
    'timestamp': 1773700000000,
  },
  {
    'role': 'assistant',
    'content': [
      {'type': 'text', 'text': _preToolText},
      {
        'type': 'toolCall',
        'id': 'functions.read:0',
        'name': 'read',
        'arguments': {'file_path': 'SOUL.md'},
      },
      {'type': 'text', 'text': ' '},
      {
        'type': 'toolCall',
        'id': 'functions.read:1',
        'name': 'read',
        'arguments': {'file_path': 'USER.md'},
      },
      {'type': 'text', 'text': ' '},
      {
        'type': 'toolCall',
        'id': 'functions.read:2',
        'name': 'read',
        'arguments': {'file_path': 'MEMORY.md'},
      },
      {'type': 'text', 'text': ' '},
    ],
    'id': 'msg-parallel-001',
    'timestamp': 1773700001000,
  },
  {
    'role': 'toolResult',
    'toolCallId': 'functions.read:0',
    'toolName': 'read',
    'content': [
      {'type': 'text', 'text': _tool0Result},
    ],
    'args': '{"file_path":"SOUL.md"}',
    'timestamp': 1773700002000,
  },
  {
    'role': 'toolResult',
    'toolCallId': 'functions.read:1',
    'toolName': 'read',
    'content': [
      {'type': 'text', 'text': _tool1Result},
    ],
    'args': '{"file_path":"USER.md"}',
    'timestamp': 1773700003000,
  },
  {
    'role': 'toolResult',
    'toolCallId': 'functions.read:2',
    'toolName': 'read',
    'content': [
      {'type': 'text', 'text': _tool2Result},
    ],
    'args': '{"file_path":"MEMORY.md"}',
    'timestamp': 1773700004000,
  },
  {
    'role': 'assistant',
    'content': [
      {'type': 'text', 'text': _postToolText},
    ],
    'id': 'msg-parallel-002',
    'timestamp': 1773700005000,
  },
];

/// Streaming: results arrive OUT OF ORDER (read:2 first, then read:0, then read:1).
final streamingEvents = <WsEvent>[
  // User local echo
  WsEvent.fromJson({
    'event': 'chat',
    'payload': {
      'type': 'message',
      'role': 'user',
      'content': _userText,
      'localEcho': true,
      'idempotencyKey': 'idem-parallel-001',
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
  // Pre-tool text
  WsEvent.fromJson({
    'event': 'chat',
    'payload': {
      'state': 'delta',
      'message': {
        'id': 'msg-parallel-001',
        'content': [
          {'type': 'text', 'text': _preToolText},
        ],
      },
    },
  }),
  // Tool starts (in order)
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
        'args': {'file_path': 'SOUL.md'},
      },
    },
    'seq': 3,
  }),
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
        'args': {'file_path': 'USER.md'},
      },
    },
    'seq': 4,
  }),
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
        'args': {'file_path': 'MEMORY.md'},
      },
    },
    'seq': 5,
  }),
  // Tool results: OUT OF ORDER -- read:2 completes first
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
    'seq': 6,
  }),
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
    'seq': 7,
  }),
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
    'seq': 8,
  }),
  // Post-tool text
  WsEvent.fromJson({
    'event': 'chat',
    'payload': {
      'state': 'delta',
      'message': {
        'id': 'msg-parallel-002',
        'content': [
          {'type': 'text', 'text': _postToolText},
        ],
      },
    },
  }),
  WsEvent.fromJson({
    'event': 'chat',
    'payload': {
      'state': 'final',
      'message': {
        'id': 'msg-parallel-002',
        'content': [
          {'type': 'text', 'text': _postToolText},
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

/// Expected entries.
final expectedEntries = <Map<String, dynamic>>[
  {'role': 'user', 'content': _userText},
  {'role': 'assistant', 'content': _preToolText},
  {'role': 'tool', 'toolName': 'read', 'toolCallId': 'functions.read:0'},
  {'role': 'tool', 'toolName': 'read', 'toolCallId': 'functions.read:1'},
  {'role': 'tool', 'toolName': 'read', 'toolCallId': 'functions.read:2'},
  {'role': 'assistant', 'content': _postToolText},
];
