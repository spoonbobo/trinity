/// Fixture: simple text-only greeting exchange (no tool calls).
/// Based on tender-claw session 6d7310c9, messages d5b5b8ed + c09b195f.
///
/// Flow: user greets -> assistant responds with text only.
import 'package:trinity_shell/models/ws_frame.dart';

const _userText = 'hi again, long time no see.';
const _assistantText =
    'Hey! Good to see you again.\n\nWhat can I help with today?';

/// What chat.history returns for this exchange.
final historyMessages = <Map<String, dynamic>>[
  {
    'role': 'user',
    'content': _userText,
    'timestamp': 1773661024351,
  },
  {
    'role': 'assistant',
    'content': [
      {
        'type': 'thinking',
        'text': 'The user is greeting me...',
      },
      {
        'type': 'text',
        'text': _assistantText,
      },
    ],
    'id': 'c09b195f',
    'timestamp': 1773661033843,
  },
];

/// The streaming event sequence a live WebSocket client would receive.
final streamingEvents = <WsEvent>[
  // User local echo
  WsEvent.fromJson({
    'event': 'chat',
    'payload': {
      'type': 'message',
      'role': 'user',
      'content': _userText,
      'localEcho': true,
      'idempotencyKey': 'idem-simple-001',
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
  // First delta
  WsEvent.fromJson({
    'event': 'chat',
    'payload': {
      'state': 'delta',
      'message': {
        'id': 'c09b195f',
        'content': [
          {'type': 'text', 'text': 'Hey! Good to see you again.'},
        ],
      },
    },
  }),
  // Second delta (accumulated)
  WsEvent.fromJson({
    'event': 'chat',
    'payload': {
      'state': 'delta',
      'message': {
        'id': 'c09b195f',
        'content': [
          {'type': 'text', 'text': _assistantText},
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
        'id': 'c09b195f',
        'content': [
          {'type': 'text', 'text': _assistantText},
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

/// Expected entries after processing (both paths should produce this).
final expectedEntries = <Map<String, dynamic>>[
  {'role': 'user', 'content': _userText},
  {'role': 'assistant', 'content': _assistantText, 'isStreaming': false},
];
