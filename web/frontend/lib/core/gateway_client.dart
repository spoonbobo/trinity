import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'auth.dart';
import '../models/ws_frame.dart';

enum ConnectionState { disconnected, connecting, connected, error }

class GatewayClient extends ChangeNotifier {
  final String url;
  final GatewayAuth auth;

  WebSocketChannel? _channel;
  ConnectionState _state = ConnectionState.disconnected;
  final _uuid = const Uuid();

  final _responseCompleters = <String, Completer<WsResponse>>{};

  final StreamController<WsEvent> _eventController =
      StreamController<WsEvent>.broadcast();

  ConnectionState get state => _state;
  Stream<WsEvent> get events => _eventController.stream;

  /// Filtered stream for chat events only.
  Stream<WsEvent> get chatEvents =>
      events.where((e) => e.event == 'chat' || e.event == 'agent');

  /// Filtered stream for approval events.
  Stream<WsEvent> get approvalEvents =>
      events.where((e) => e.event == 'exec.approval.requested');

  GatewayClient({required this.url, required this.auth});

  Future<void> connect() async {
    if (_state == ConnectionState.connected ||
        _state == ConnectionState.connecting) return;

    _state = ConnectionState.connecting;
    notifyListeners();

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      await _channel!.ready;
      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );
    } catch (e) {
      _state = ConnectionState.error;
      notifyListeners();
      rethrow;
    }
  }

  void _onMessage(dynamic raw) {
    final frame = WsFrame.parse(raw as String);

    switch (frame.type) {
      case FrameType.event:
        final event = frame.event!;
        if (event.event == 'connect.challenge') {
          _handleChallenge(event);
        } else {
          _eventController.add(event);
        }
        break;
      case FrameType.res:
        final response = frame.response!;
        final completer = _responseCompleters.remove(response.id);
        if (completer != null) {
          completer.complete(response);
        }
        // Also emit hello-ok as a state change
        if (response.ok &&
            response.payload?['type'] == 'hello-ok') {
          _state = ConnectionState.connected;
          notifyListeners();
        }
        break;
      case FrameType.req:
        break;
    }
  }

  void _handleChallenge(WsEvent event) {
    final nonce = event.payload['nonce'] as String?;
    _sendConnect(nonce);
  }

  void _sendConnect(String? nonce) {
    final params = <String, dynamic>{
      'minProtocol': 3,
      'maxProtocol': 3,
      'client': {
        'id': 'trinity-shell',
        'version': '0.1.0',
        'platform': 'web',
        'mode': 'operator',
      },
      'role': 'operator',
      'scopes': ['operator.read', 'operator.write', 'operator.approvals'],
      'caps': [],
      'commands': [],
      'permissions': {},
      'locale': 'en-US',
      'userAgent': 'trinity-shell/0.1.0',
      ...auth.toConnectParams(),
    };

    sendRequest('connect', params);
  }

  /// Send a typed request and return a future that resolves with the response.
  Future<WsResponse> sendRequest(
    String method,
    Map<String, dynamic> params,
  ) {
    final id = _uuid.v4();
    final request = WsRequest(id: id, method: method, params: params);
    final completer = Completer<WsResponse>();
    _responseCompleters[id] = completer;
    _channel?.sink.add(request.encode());
    return completer.future;
  }

  /// Send a chat message to the agent.
  Future<WsResponse> sendChatMessage(String message,
      {String sessionKey = 'main'}) {
    return sendRequest('chat.send', {
      'message': message,
      'sessionKey': sessionKey,
      'idempotencyKey': _uuid.v4(),
    });
  }

  /// Fetch chat history.
  Future<WsResponse> getChatHistory({
    String sessionKey = 'main',
    int limit = 50,
  }) {
    return sendRequest('chat.history', {
      'sessionKey': sessionKey,
      'limit': limit,
    });
  }

  /// Abort an in-progress agent run.
  Future<WsResponse> abortChat({String sessionKey = 'main'}) {
    return sendRequest('chat.abort', {
      'sessionKey': sessionKey,
    });
  }

  /// Resolve an exec approval request.
  Future<WsResponse> resolveApproval(String requestId, bool approve) {
    return sendRequest('exec.approval.resolve', {
      'requestId': requestId,
      'approved': approve,
    });
  }

  void _onError(dynamic error) {
    _state = ConnectionState.error;
    notifyListeners();
  }

  void _onDone() {
    _state = ConnectionState.disconnected;
    _responseCompleters.clear();
    notifyListeners();
  }

  void disconnect() {
    _channel?.sink.close();
    _state = ConnectionState.disconnected;
    _responseCompleters.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    _eventController.close();
    super.dispose();
  }
}
