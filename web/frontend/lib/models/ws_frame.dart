import 'dart:convert';

enum FrameType { req, res, event }

class WsRequest {
  final String id;
  final String method;
  final Map<String, dynamic> params;

  const WsRequest({
    required this.id,
    required this.method,
    this.params = const {},
  });

  Map<String, dynamic> toJson() => {
        'type': 'req',
        'id': id,
        'method': method,
        'params': params,
      };

  String encode() => jsonEncode(toJson());
}

class WsResponse {
  final String id;
  final bool ok;
  final Map<String, dynamic>? payload;
  final Map<String, dynamic>? error;

  const WsResponse({
    required this.id,
    required this.ok,
    this.payload,
    this.error,
  });

  factory WsResponse.fromJson(Map<String, dynamic> json) => WsResponse(
        id: json['id'] as String,
        ok: json['ok'] as bool,
        payload: json['payload'] as Map<String, dynamic>?,
        error: json['error'] as Map<String, dynamic>?,
      );
}

class WsEvent {
  final String event;
  final Map<String, dynamic> payload;
  final int? seq;
  final int? stateVersion;

  const WsEvent({
    required this.event,
    required this.payload,
    this.seq,
    this.stateVersion,
  });

  factory WsEvent.fromJson(Map<String, dynamic> json) => WsEvent(
        event: json['event'] as String,
        payload: (json['payload'] as Map<String, dynamic>?) ?? {},
        seq: json['seq'] as int?,
        stateVersion: json['stateVersion'] as int?,
      );
}

class WsFrame {
  final FrameType type;
  final WsRequest? request;
  final WsResponse? response;
  final WsEvent? event;

  const WsFrame._({
    required this.type,
    this.request,
    this.response,
    this.event,
  });

  factory WsFrame.parse(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final typeStr = json['type'] as String;

    switch (typeStr) {
      case 'req':
        return WsFrame._(
          type: FrameType.req,
          request: WsRequest(
            id: json['id'] as String,
            method: json['method'] as String,
            params: (json['params'] as Map<String, dynamic>?) ?? {},
          ),
        );
      case 'res':
        return WsFrame._(
          type: FrameType.res,
          response: WsResponse.fromJson(json),
        );
      case 'event':
        return WsFrame._(
          type: FrameType.event,
          event: WsEvent.fromJson(json),
        );
      default:
        throw FormatException('Unknown frame type: $typeStr');
    }
  }
}
