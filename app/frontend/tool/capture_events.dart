// ignore_for_file: avoid_print
/// Standalone Dart CLI tool to capture OpenClaw WebSocket events as test fixtures.
///
/// Usage:
///   dart run tool/capture_events.dart \
///     --url ws://localhost:18789 \
///     --token <gateway-token> \
///     --message "read my MEMORY.md file" \
///     --session main \
///     --output test/features/chat/fixtures/text_then_tools.dart \
///     --name textThenTools \
///     --timeout 60
///
/// This tool does NOT depend on Flutter — only dart:io + pub packages.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// ---------------------------------------------------------------------------
// Argument parsing (no dependency on package:args)
// ---------------------------------------------------------------------------

class _Args {
  final String url;
  final String token;
  final String message;
  final String session;
  final String? output;
  final String name;
  final int timeout;

  _Args({
    required this.url,
    required this.token,
    required this.message,
    required this.session,
    required this.output,
    required this.name,
    required this.timeout,
  });

  factory _Args.parse(List<String> raw) {
    String? url, token, message, session, output, name;
    int? timeout;

    for (var i = 0; i < raw.length; i++) {
      final arg = raw[i];
      switch (arg) {
        case '--url':
          url = _next(raw, i++, '--url');
        case '--token':
          token = _next(raw, i++, '--token');
        case '--message':
          message = _next(raw, i++, '--message');
        case '--session':
          session = _next(raw, i++, '--session');
        case '--output':
          output = _next(raw, i++, '--output');
        case '--name':
          name = _next(raw, i++, '--name');
        case '--timeout':
          timeout = int.tryParse(_next(raw, i++, '--timeout'));
          if (timeout == null || timeout <= 0) {
            _exitUsage('--timeout must be a positive integer');
          }
        case '--help':
        case '-h':
          _exitUsage();
        default:
          _exitUsage('Unknown argument: $arg');
      }
    }

    if (url == null) _exitUsage('--url is required');
    if (token == null) _exitUsage('--token is required');
    if (message == null) _exitUsage('--message is required');

    return _Args(
      url: url!,
      token: token!,
      message: message!,
      session: session ?? 'main',
      output: output,
      name: name ?? 'captured',
      timeout: timeout ?? 60,
    );
  }

  static String _next(List<String> raw, int i, String flag) {
    if (i + 1 >= raw.length) _exitUsage('$flag requires a value');
    return raw[i + 1];
  }

  static Never _exitUsage([String? error]) {
    if (error != null) stderr.writeln('Error: $error\n');
    stderr.writeln('''
Usage: dart run tool/capture_events.dart [options]

Required:
  --url <ws-url>        WebSocket URL (e.g. ws://localhost:18789)
  --token <token>       Gateway auth token
  --message <text>      Chat message to send

Optional:
  --session <key>       Session key (default: main)
  --output <path>       Output file path (default: stdout)
  --name <prefix>       Fixture variable prefix (default: captured)
  --timeout <seconds>   Timeout in seconds (default: 60)
  --help, -h            Show this help
''');
    exit(error != null ? 1 : 0);
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

Future<void> main(List<String> arguments) async {
  final args = _Args.parse(arguments);
  final uuid = const Uuid();

  print('Connecting to ${args.url} ...');

  // ---- Build WebSocket URI with auth ----
  final wsUri = Uri.parse(args.url);
  final authedUri = wsUri.replace(queryParameters: {
    ...wsUri.queryParameters,
    'token': args.token,
  });

  late final WebSocketChannel channel;
  try {
    channel = IOWebSocketChannel.connect(
      authedUri,
      pingInterval: const Duration(seconds: 15),
    );
    await channel.ready;
  } catch (e) {
    stderr.writeln('Failed to connect: $e');
    exit(1);
  }

  print('Connected. Waiting for challenge...');

  // ---- State ----
  final collectedEvents = <Map<String, dynamic>>[];
  final responseCompleters = <String, Completer<Map<String, dynamic>>>{};
  var handshakeComplete = false;
  var runComplete = false;
  String? chatSendId;

  // ---- Helpers ----
  void send(Map<String, dynamic> frame) {
    final encoded = jsonEncode(frame);
    channel.sink.add(encoded);
  }

  Future<Map<String, dynamic>> sendRequest(
    String method,
    Map<String, dynamic> params,
  ) {
    final id = uuid.v4();
    final completer = Completer<Map<String, dynamic>>();
    responseCompleters[id] = completer;
    send({'type': 'req', 'id': id, 'method': method, 'params': params});
    return completer.future.timeout(
      Duration(seconds: args.timeout),
      onTimeout: () {
        responseCompleters.remove(id);
        throw TimeoutException('Request $method timed out after ${args.timeout}s');
      },
    );
  }

  void sendConnect(String? nonce) {
    final id = uuid.v4();
    final completer = Completer<Map<String, dynamic>>();
    responseCompleters[id] = completer;
    send({
      'type': 'req',
      'id': id,
      'method': 'connect',
      'params': {
        'minProtocol': 3,
        'maxProtocol': 3,
        'client': {
          'id': 'capture-tool',
          'version': '1.0',
          'platform': 'cli',
          'mode': 'webchat',
        },
        'role': 'operator',
        'scopes': ['operator.read', 'operator.write'],
        'caps': ['tool-events'],
        'commands': <String>[],
        'permissions': <String, dynamic>{},
        'locale': 'en-US',
        'userAgent': 'capture-tool/1.0',
        'auth': {'token': args.token},
        'device': {
          'id': 'capture-device',
          'name': 'capture',
          'platform': 'cli',
        },
      },
    });
    // hello-ok response handled inline in message handler
    completer.future.then((_) {
      handshakeComplete = true;
      print('Handshake complete. Sending chat message...');

      // Send chat.send
      chatSendId = uuid.v4();
      final chatCompleter = Completer<Map<String, dynamic>>();
      responseCompleters[chatSendId!] = chatCompleter;
      send({
        'type': 'req',
        'id': chatSendId,
        'method': 'chat.send',
        'params': {
          'message': args.message,
          'sessionKey': args.session,
          'idempotencyKey': uuid.v4(),
        },
      });
    });
  }

  // ---- Overall timeout ----
  final overallTimer = Timer(Duration(seconds: args.timeout), () {
    stderr.writeln('Timeout: no completion after ${args.timeout}s');
    channel.sink.close();
    exit(1);
  });

  // ---- Listen ----
  final done = Completer<void>();

  channel.stream.listen(
    (raw) {
      if (raw is! String) return;
      late final Map<String, dynamic> json;
      try {
        json = jsonDecode(raw) as Map<String, dynamic>;
      } catch (e) {
        stderr.writeln('Ignoring non-JSON frame: $e');
        return;
      }

      final type = json['type'] as String? ?? '';

      switch (type) {
        case 'event':
          final event = json['event'] as String? ?? '';
          if (event == 'connect.challenge') {
            final payload = json['payload'] as Map<String, dynamic>? ?? {};
            final nonce = payload['nonce'] as String?;
            final noncePreview = nonce != null && nonce.length > 8
                ? '${nonce.substring(0, 8)}...'
                : nonce ?? '(none)';
            print('Received challenge (nonce=$noncePreview)');
            sendConnect(nonce);
          } else if (handshakeComplete &&
              (event == 'chat' || event == 'agent')) {
            // Record the event
            collectedEvents.add(json);
            // Pretty status
            final payload = json['payload'] as Map<String, dynamic>? ?? {};
            final preview = _eventPreview(event, payload);
            print('  [${collectedEvents.length}] $event: $preview');

            // Detect run completion
            if (_isRunComplete(event, payload)) {
              runComplete = true;
              print('\nRun complete. Fetching chat history...');
              _fetchHistoryAndFinish(
                sendRequest: sendRequest,
                args: args,
                collectedEvents: collectedEvents,
                overallTimer: overallTimer,
                channel: channel,
                done: done,
              );
            }
          }

        case 'res':
          final id = json['id'] as String? ?? '';
          final completer = responseCompleters.remove(id);
          if (completer != null && !completer.isCompleted) {
            completer.complete(json);
          }
          // Check for errors on chat.send response
          if (id == chatSendId) {
            final ok = json['ok'] as bool? ?? false;
            if (!ok) {
              stderr.writeln('chat.send failed: ${jsonEncode(json)}');
              channel.sink.close();
              exit(1);
            }
            print('chat.send acknowledged. Recording events...\n');
          }
      }
    },
    onError: (e) {
      stderr.writeln('WebSocket error: $e');
      overallTimer.cancel();
      if (!done.isCompleted) done.completeError(e);
    },
    onDone: () {
      if (!runComplete) {
        stderr.writeln(
          'WebSocket closed before run completed. '
          'Captured ${collectedEvents.length} events so far.',
        );
      }
      overallTimer.cancel();
      if (!done.isCompleted) done.complete();
    },
  );

  await done.future;
}

// ---------------------------------------------------------------------------
// Run-completion detection
// ---------------------------------------------------------------------------

/// Returns true if this event signals the agent run is finished.
bool _isRunComplete(String event, Map<String, dynamic> payload) {
  // agent lifecycle end
  if (event == 'agent') {
    final stream = payload['stream'] as String?;
    final data = payload['data'] as Map<String, dynamic>?;
    if (stream == 'lifecycle' && data?['phase'] == 'end') return true;
  }
  // chat done
  if (event == 'chat') {
    final state = payload['state'] as String?;
    if (state == 'done') return true;
    // Also check for error state as terminal
    if (state == 'error') return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Post-run: fetch history and emit fixture
// ---------------------------------------------------------------------------

Future<void> _fetchHistoryAndFinish({
  required Future<Map<String, dynamic>> Function(
          String method, Map<String, dynamic> params)
      sendRequest,
  required _Args args,
  required List<Map<String, dynamic>> collectedEvents,
  required Timer overallTimer,
  required WebSocketChannel channel,
  required Completer<void> done,
}) async {
  try {
    final historyRes = await sendRequest('chat.history', {
      'sessionKey': args.session,
      'limit': 10,
    });

    overallTimer.cancel();

    final historyOk = historyRes['ok'] as bool? ?? false;
    List<dynamic> historyMessages = [];
    if (historyOk) {
      final payload = historyRes['payload'] as Map<String, dynamic>? ?? {};
      historyMessages = payload['messages'] as List<dynamic>? ?? [];
      print('Got ${historyMessages.length} history messages.');
    } else {
      stderr.writeln(
          'Warning: chat.history failed: ${jsonEncode(historyRes)}');
    }

    // ---- Generate fixture ----
    final fixtureSource = _generateFixture(
      args: args,
      events: collectedEvents,
      history: historyMessages,
    );

    if (args.output != null) {
      final outFile = File(args.output!);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsString(fixtureSource);
      print('\nFixture written to: ${args.output}');
    } else {
      print('\n--- FIXTURE OUTPUT ---\n');
      print(fixtureSource);
    }

    print('\nDone: ${collectedEvents.length} events captured.');
    channel.sink.close();
    if (!done.isCompleted) done.complete();
  } catch (e) {
    overallTimer.cancel();
    stderr.writeln('Error fetching history: $e');
    // Still output what we have
    final fixtureSource = _generateFixture(
      args: args,
      events: collectedEvents,
      history: [],
    );
    if (args.output != null) {
      final outFile = File(args.output!);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsString(fixtureSource);
      print('\nFixture written to: ${args.output} (no history)');
    } else {
      print('\n--- FIXTURE OUTPUT ---\n');
      print(fixtureSource);
    }
    channel.sink.close();
    if (!done.isCompleted) done.complete();
  }
}

// ---------------------------------------------------------------------------
// Fixture codegen
// ---------------------------------------------------------------------------

String _generateFixture({
  required _Args args,
  required List<Map<String, dynamic>> events,
  required List<dynamic> history,
}) {
  final now = DateTime.now().toUtc().toIso8601String();
  final buf = StringBuffer();

  buf.writeln('// AUTO-GENERATED by tool/capture_events.dart');
  buf.writeln('// Captured from: ${args.url} at $now');
  buf.writeln('// Message: ${_dartStringEscape(args.message)}');
  buf.writeln('// Session: ${args.session}');
  buf.writeln();

  // ---- Streaming events ----
  buf.writeln('/// Streaming events recorded from live WebSocket connection.');
  buf.writeln(
      'final ${args.name}StreamingEvents = <Map<String, dynamic>>[');
  for (final evt in events) {
    // Extract only event-level fields (event, payload, seq, stateVersion)
    final slim = <String, dynamic>{
      'event': evt['event'],
      'payload': evt['payload'],
    };
    if (evt['seq'] != null) slim['seq'] = evt['seq'];
    if (evt['stateVersion'] != null) {
      slim['stateVersion'] = evt['stateVersion'];
    }
    buf.writeln('  ${_dartMapLiteral(slim)},');
  }
  buf.writeln('];');
  buf.writeln();

  // ---- History ----
  buf.writeln(
      '/// History messages from chat.history response after the run completed.');
  buf.writeln(
      'final ${args.name}HistoryMessages = <Map<String, dynamic>>[');
  for (final msg in history) {
    if (msg is Map<String, dynamic>) {
      buf.writeln('  ${_dartMapLiteral(msg)},');
    }
  }
  buf.writeln('];');

  return buf.toString();
}

/// Convert an arbitrary JSON-compatible value to a Dart literal string.
String _dartLiteral(dynamic value) {
  if (value == null) return 'null';
  if (value is bool) return value.toString();
  if (value is int) return value.toString();
  if (value is double) return value.toString();
  if (value is String) return "'${_dartStringEscape(value)}'";
  if (value is List) {
    if (value.isEmpty) return '<dynamic>[]';
    final items = value.map(_dartLiteral).join(', ');
    return '<dynamic>[$items]';
  }
  if (value is Map) {
    return _dartMapLiteral(Map<String, dynamic>.from(value));
  }
  // Fallback
  return "'${_dartStringEscape(value.toString())}'";
}

String _dartMapLiteral(Map<String, dynamic> map) {
  if (map.isEmpty) return '<String, dynamic>{}';
  final entries = map.entries.map((e) {
    return "'${_dartStringEscape(e.key)}': ${_dartLiteral(e.value)}";
  }).join(', ');
  return '<String, dynamic>{$entries}';
}

String _dartStringEscape(String s) {
  return s
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t');
}

// ---------------------------------------------------------------------------
// Pretty preview for console output
// ---------------------------------------------------------------------------

String _eventPreview(String event, Map<String, dynamic> payload) {
  if (event == 'agent') {
    final stream = payload['stream'] as String? ?? '';
    final data = payload['data'];
    if (data is Map<String, dynamic>) {
      final phase = data['phase'] as String?;
      final name = data['name'] as String?;
      if (phase != null) return '$stream/$phase';
      if (name != null) return '$stream/$name';
    }
    return stream;
  }
  if (event == 'chat') {
    final state = payload['state'] as String?;
    if (state == 'delta') {
      final msg = payload['message'] as Map<String, dynamic>?;
      final content = msg?['content'] as List<dynamic>?;
      if (content != null && content.isNotEmpty) {
        final first = content[0];
        if (first is Map && first['type'] == 'text') {
          final text = first['text'] as String? ?? '';
          final preview =
              text.length > 60 ? '${text.substring(0, 60)}...' : text;
          return 'delta: ${preview.replaceAll('\n', '\\n')}';
        }
        return 'delta: ${first is Map ? first['type'] : '?'}';
      }
      return 'delta';
    }
    return state ?? '?';
  }
  return '?';
}
