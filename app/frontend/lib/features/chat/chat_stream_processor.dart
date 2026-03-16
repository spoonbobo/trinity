import 'dart:convert';
import '../../models/ws_frame.dart';
import 'chat_entry.dart';

/// Pure-logic event processor for chat streaming.
/// No Flutter dependency -- fully unit-testable.
///
/// Converts WsEvents (from live streaming) and history payloads (from
/// chat.history) into a flat [entries] list that the UI renders.
class ChatStreamProcessor {
  static const int maxEntries = 500;

  final List<ChatEntry> entries = [];
  bool agentThinking = false;

  // Turn tracking
  bool _toolCardsInsertedSinceLastAssistant = false;
  final Set<String> _seenToolCallIds = {};

  // Optimistic echo
  final List<PendingUserEcho> _pendingUserEchoes = [];

  // Stream key tracking
  int? _currentRunFirstAssistantSeq;
  bool currentRunHadToolGap = false;

  // A2UI
  String? lastCanvasSurface;

  /// Payloads for A2UI events that need to be emitted by the widget layer.
  /// The widget consumes and clears this list after each processEvent call.
  final List<String> pendingA2UIPayloads = [];

  // -----------------------------------------------------------------------
  // Public API
  // -----------------------------------------------------------------------

  /// Set by mutation methods to signal that state changed.
  bool _dirty = false;

  /// Process a single WsEvent from the chatEvents stream.
  /// Returns true if any state changed (so widget knows to rebuild).
  bool processEvent(WsEvent event) {
    _dirty = false;
    try {
      _processEventInner(event);
      _capEntries();
    } catch (_) {
      // Swallow -- caller can log if desired.
    }
    return _dirty;
  }

  /// Load entries from a chat.history response payload.
  /// Clears existing entries first.
  void loadHistory(List<dynamic> messages) {
    entries.clear();
    for (final msg in messages) {
      if (msg is! Map<String, dynamic>) continue;
      final rawRole = msg['role'] as String? ?? 'system';
      final role = rawRole == 'toolResult' ? 'tool' : rawRole;

      final toolName = msg['toolName'] as String? ??
          msg['name'] as String? ??
          (role == 'tool' ? 'tool' : null);
      final toolCallId = role == 'tool'
          ? (msg['toolCallId'] as String? ?? msg['id'] as String?)
          : null;

      // Extract timestamp
      DateTime? timestamp;
      final ts = msg['timestamp'] ?? msg['createdAt'] ?? msg['ts'];
      if (ts is num) {
        timestamp =
            DateTime.fromMillisecondsSinceEpoch(ts.toInt(), isUtc: true);
      } else if (ts is String) {
        timestamp = DateTime.tryParse(ts);
      }

      if (role == 'assistant') {
        final contentRaw = msg['content'];
        if (contentRaw is List) {
          // Structure-aware parsing: handle interleaved text + toolCall blocks
          String preToolText = '';
          bool hitToolCall = false;

          for (final block in contentRaw) {
            if (block is! Map<String, dynamic>) continue;
            final type = block['type'] as String?;
            if (type == 'thinking') continue;
            if (type == 'toolCall') {
              hitToolCall = true;
              continue;
            }
            if (type == 'text') {
              if (!hitToolCall) {
                preToolText += block['text'] as String? ?? '';
              }
              // Text blocks AFTER toolCall are whitespace spacers -- skip
            }
          }

          if (hitToolCall) {
            // Mixed text + toolCall message: only add pre-tool text
            preToolText = preToolText.trim();
            if (preToolText.isNotEmpty) {
              final historyAttachments =
                  extractImageAttachments(msg['content']);
              entries.add(ChatEntry(
                role: 'assistant',
                content: preToolText,
                timestamp: timestamp,
                attachments:
                    historyAttachments.isNotEmpty ? historyAttachments : null,
              ));
            }
            // toolResult messages will follow as separate entries
          } else {
            // Pure text message (no toolCalls) -- join all text blocks
            var content = extractContent(contentRaw);
            if (content.contains('__A2UI__')) content = 'Canvas updated';
            if (content.isNotEmpty) {
              final historyAttachments =
                  extractImageAttachments(msg['content']);
              entries.add(ChatEntry(
                role: 'assistant',
                content: content,
                timestamp: timestamp,
                attachments:
                    historyAttachments.isNotEmpty ? historyAttachments : null,
              ));
            }
          }
        } else {
          // Plain string content
          var content = contentRaw?.toString() ?? '';
          if (content.contains('__A2UI__')) content = 'Canvas updated';
          if (content.isNotEmpty) {
            entries.add(ChatEntry(
              role: 'assistant',
              content: content,
              timestamp: timestamp,
            ));
          }
        }
      } else if (role == 'tool') {
        var content = extractContent(msg['content']);
        if (content.contains('__A2UI__')) content = 'Canvas updated';

        Map<String, dynamic>? meta;
        if (toolName != null) {
          final argsRaw =
              msg['args']?.toString() ?? msg['input']?.toString() ?? '';
          meta = ChatEntry.parseToolMetadata(toolName, argsRaw);
        }
        entries.add(ChatEntry(
          role: 'tool',
          content: content,
          toolName: toolName,
          toolCallId: toolCallId,
          timestamp: timestamp,
          metadata: meta,
        ));
      } else if (role == 'user') {
        var content = extractContent(msg['content']);
        final historyAttachments = extractImageAttachments(msg['content']);
        entries.add(ChatEntry(
          role: 'user',
          content: content,
          timestamp: timestamp,
          attachments:
              historyAttachments.isNotEmpty ? historyAttachments : null,
        ));
      } else {
        // system or unknown role
        var content = extractContent(msg['content']);
        if (content.isNotEmpty) {
          entries.add(ChatEntry(
            role: role,
            content: content,
            timestamp: timestamp,
          ));
        }
      }
    }

    // Seed last canvas surface from history
    _seedLastCanvasSurface(messages);
  }

  /// Clear all state.
  void clear() {
    entries.clear();
    agentThinking = false;
    _dirty = false;
    _toolCardsInsertedSinceLastAssistant = false;
    _seenToolCallIds.clear();
    _pendingUserEchoes.clear();
    _currentRunFirstAssistantSeq = null;
    currentRunHadToolGap = false;
    lastCanvasSurface = null;
    pendingA2UIPayloads.clear();
  }

  // -----------------------------------------------------------------------
  // Event processing (mirrors _handleChatEventInner)
  // -----------------------------------------------------------------------

  void _processEventInner(WsEvent event) {
    final payload = event.payload;

    if (event.event == 'chat') {
      _processChatEvent(payload);
    } else if (event.event == 'agent') {
      _processAgentEvent(payload);
    }
  }

  void _processChatEvent(Map<String, dynamic> payload) {
    _dirty = true; // Most chat events mutate entries or agentThinking
    final state = payload['state'] as String?;
    final type = payload['type'] as String?;

    if (type == 'message' && payload['role'] == 'user') {
      final isLocalEcho = payload['localEcho'] == true;
      final content = payload['content'] as String? ?? '';
      final idempotencyKey = payload['idempotencyKey'] as String?;
      final rawAttachments = payload['attachments'];
      List<Map<String, dynamic>>? attachments;
      if (rawAttachments is List) {
        attachments =
            rawAttachments.whereType<Map<String, dynamic>>().toList();
      }

      if (isLocalEcho) {
        _recordOptimisticUser(content, idempotencyKey: idempotencyKey);
      } else if (_consumeOptimisticUser(content,
          idempotencyKey: idempotencyKey)) {
        return;
      }

      if (!isLocalEcho &&
          entries.isNotEmpty &&
          entries.last.role == 'user' &&
          entries.last.content == content) {
        return;
      }
      entries.add(ChatEntry(
        role: 'user',
        content: content,
        attachments: attachments,
      ));
    } else if (state == 'delta' || state == 'final' || state == 'aborted') {
      final message = payload['message'];
      if (message is! Map<String, dynamic>) return;
      final assistantStreamKey = _assistantStreamKey(payload, message);
      final contentList = message['content'];
      if (contentList is! List || contentList.isEmpty) return;
      String text = '';
      for (final block in contentList) {
        if (block is Map<String, dynamic> && block['type'] == 'text') {
          text = block['text'] as String? ?? '';
          break;
        }
      }

      if (state == 'final' || state == 'aborted') {
        final keyedIdx = assistantStreamKey == null
            ? -1
            : _findAssistantIndexByStreamKey(assistantStreamKey);
        final streamingIdx = keyedIdx != -1
            ? keyedIdx
            : entries.lastIndexWhere(
                (e) => e.role == 'assistant' && e.isStreaming,
              );
        agentThinking = false;
        if (streamingIdx != -1) {
          if (text.isEmpty) {
            entries.removeAt(streamingIdx);
          } else {
            entries[streamingIdx] = entries[streamingIdx].copyWith(
              content: text,
              isStreaming: false,
            );
          }
        } else if (text.isNotEmpty) {
          final lastAssistantIdx =
              entries.lastIndexWhere((e) => e.role == 'assistant');
          if (lastAssistantIdx != -1 &&
              !entries[lastAssistantIdx].isStreaming &&
              entries[lastAssistantIdx].content == text) {
            return;
          }
          entries.add(ChatEntry(role: 'assistant', content: text));
        }
      } else {
        // Delta
        if (_toolCardsInsertedSinceLastAssistant && text.isNotEmpty) {
          // Tool cards were inserted after previous assistant text.
          // Create a NEW assistant entry after the tool cards.
          agentThinking = false;
          entries.add(ChatEntry(
            role: 'assistant',
            content: text,
            isStreaming: true,
            metadata: assistantStreamKey == null
                ? null
                : {'_streamKey': assistantStreamKey},
          ));
          _toolCardsInsertedSinceLastAssistant = false;
        } else {
          // Normal path: find existing streaming entry or create new one
          final keyedStreamingIdx = assistantStreamKey == null
              ? -1
              : _findAssistantIndexByStreamKey(assistantStreamKey,
                  requireStreaming: true);
          final keyedIdx = assistantStreamKey == null
              ? -1
              : _findAssistantIndexByStreamKey(assistantStreamKey);
          final streamingIdx = keyedStreamingIdx != -1
              ? keyedStreamingIdx
              : (keyedIdx != -1
                  ? keyedIdx
                  : entries.lastIndexWhere(
                      (e) => e.role == 'assistant' && e.isStreaming,
                    ));
          agentThinking = false;
          if (streamingIdx != -1) {
            entries[streamingIdx] = entries[streamingIdx].copyWith(
              content: text,
              isStreaming: true,
            );
          } else if (text.isNotEmpty) {
            entries.add(ChatEntry(
              role: 'assistant',
              content: text,
              isStreaming: true,
              metadata: assistantStreamKey == null
                  ? null
                  : {'_streamKey': assistantStreamKey},
            ));
          }
        }
      }
    }
  }

  void _processAgentEvent(Map<String, dynamic> payload) {
    _dirty = true; // Most agent events mutate entries or agentThinking
    final stream = payload['stream'] as String?;
    final data = payload['data'];
    final dataMap = data is Map<String, dynamic> ? data : null;

    // Detect tool call seq gap
    if (stream == 'assistant' && _currentRunFirstAssistantSeq == null) {
      final seq = payload['seq'];
      if (seq is int) {
        _currentRunFirstAssistantSeq = seq;
        if (seq >= 3) {
          currentRunHadToolGap = true;
        }
      }
    }

    if (stream == 'lifecycle') {
      final phase = dataMap?['phase'] as String?;
      if (phase == 'start') {
        agentThinking = true;
        currentRunHadToolGap = false;
        _currentRunFirstAssistantSeq = null;
        _toolCardsInsertedSinceLastAssistant = false;
        _seenToolCallIds.clear();
      } else if (phase == 'end') {
        agentThinking = false;
        _toolCardsInsertedSinceLastAssistant = false;
        // Clear stale streaming state for tool cards only.
        for (int i = entries.length - 1; i >= 0; i--) {
          if (entries[i].isStreaming && entries[i].role == 'tool') {
            entries[i] = entries[i].copyWith(isStreaming: false);
          }
          if (entries[i].role == 'user') break;
        }
      }
    } else if (stream == 'tool_call' || stream == 'tool') {
      final toolName = dataMap?['tool'] as String? ??
          dataMap?['name'] as String? ??
          'tool';
      final phase = dataMap?['phase'] as String?;
      final toolCallId =
          dataMap?['id'] as String? ?? dataMap?['toolCallId'] as String?;
      final result = dataMap?['result']?.toString() ??
          dataMap?['output']?.toString() ??
          '';

      if (phase == 'end' || phase == 'result') {
        // Tool finished
        final a2uiPayload = extractA2UIText(result);
        if (a2uiPayload != null) {
          pendingA2UIPayloads.add(a2uiPayload);
          _updateLastToolEntry('Canvas updated', toolCallId: toolCallId);
        } else {
          final mediaArtifacts = extractMediaArtifacts(result);
          final displayResult = result.isNotEmpty ? result : 'Done';
          _updateLastToolEntry(displayResult, toolCallId: toolCallId);
          for (final artifact in mediaArtifacts) {
            final url = artifact['url'] as String? ?? '';
            final name = artifact['fileName'] as String? ?? 'file';
            final mimeType =
                artifact['mimeType'] as String? ?? 'application/octet-stream';
            final isImage = artifact['isImage'] == true;
            entries.add(ChatEntry(
              role: 'assistant',
              content: isImage
                  ? '![Generated image]($url)'
                  : '[Generated file: $name]($url)',
              attachments: isImage
                  ? null
                  : [
                      {
                        'fileName': name,
                        'mimeType': mimeType,
                        'url': url,
                        'type': 'file',
                      }
                    ],
            ));
          }
          _capEntries();
        }
      } else {
        // Tool started or in progress -- dedup check
        if (toolCallId != null && toolCallId.isNotEmpty) {
          if (_seenToolCallIds.contains(toolCallId)) return;
          _seenToolCallIds.add(toolCallId);
        }
        final argsRaw = dataMap?['args'];
        final argsText = argsRaw?.toString() ?? '';
        final meta =
            ChatEntry.parseToolMetadataDynamic(toolName, argsRaw);
        agentThinking = false;
        entries.add(ChatEntry(
          role: 'tool',
          content: argsText,
          toolName: toolName,
          toolCallId: toolCallId,
          isStreaming: true,
          metadata: meta,
          startedAt: DateTime.now(),
        ));
        _toolCardsInsertedSinceLastAssistant = true;
      }
    } else if (stream == 'tool_result') {
      final toolCallId =
          dataMap?['id'] as String? ?? dataMap?['toolCallId'] as String?;
      final result = dataMap?['result']?.toString() ??
          dataMap?['output']?.toString() ??
          '';
      final a2uiPayload = extractA2UIText(result);
      if (a2uiPayload != null) {
        pendingA2UIPayloads.add(a2uiPayload);
        _updateLastToolEntry('Canvas updated', toolCallId: toolCallId);
      } else {
        _updateLastToolEntry(result.isNotEmpty ? result : 'Done',
            toolCallId: toolCallId);
      }
    }
  }

  // -----------------------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------------------

  String? _assistantStreamKey(
    Map<String, dynamic> payload,
    Map<String, dynamic> message,
  ) {
    final candidates = [
      message['id'],
      message['messageId'],
      payload['messageId'],
      payload['id'],
      payload['runId'],
      message['runId'],
      payload['turnId'],
      message['turnId'],
    ];
    for (final candidate in candidates) {
      final value = candidate?.toString();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  int _findAssistantIndexByStreamKey(
    String streamKey, {
    bool requireStreaming = false,
  }) {
    for (int i = entries.length - 1; i >= 0; i--) {
      final entry = entries[i];
      if (entry.role != 'assistant') continue;
      if (requireStreaming && !entry.isStreaming) continue;
      final key = entry.metadata?['_streamKey']?.toString();
      if (key == streamKey) return i;
    }
    return -1;
  }

  void _updateLastToolEntry(
    String content, {
    bool isStreaming = false,
    String? toolCallId,
  }) {
    // First pass: match by toolCallId
    if (toolCallId != null && toolCallId.isNotEmpty) {
      for (int i = entries.length - 1; i >= 0; i--) {
        if (entries[i].role == 'tool' && entries[i].toolCallId == toolCallId) {
          final elapsed = entries[i].startedAt != null
              ? DateTime.now().difference(entries[i].startedAt!)
              : null;
          entries[i] = entries[i].copyWith(
            content: content,
            isStreaming: isStreaming,
            elapsed: elapsed,
          );
          return;
        }
        if (entries[i].role == 'user') break;
      }
    }
    // Fallback: most recent tool entry in current turn
    for (int i = entries.length - 1; i >= 0; i--) {
      if (entries[i].role == 'tool') {
        final elapsed = entries[i].startedAt != null
            ? DateTime.now().difference(entries[i].startedAt!)
            : null;
        entries[i] = entries[i].copyWith(
          content: content,
          isStreaming: isStreaming,
          elapsed: elapsed,
        );
        return;
      }
      if (entries[i].role == 'user') break;
    }
  }

  void _recordOptimisticUser(String content, {String? idempotencyKey}) {
    final now = DateTime.now();
    _pendingUserEchoes.add(PendingUserEcho(
      content: content,
      idempotencyKey: idempotencyKey,
      createdAt: now,
    ));
    _pendingUserEchoes.removeWhere(
      (entry) => now.difference(entry.createdAt).inSeconds > 20,
    );
  }

  bool _consumeOptimisticUser(String content, {String? idempotencyKey}) {
    final now = DateTime.now();
    _pendingUserEchoes.removeWhere(
      (entry) => now.difference(entry.createdAt).inSeconds > 20,
    );
    for (int i = 0; i < _pendingUserEchoes.length; i++) {
      final pending = _pendingUserEchoes[i];
      final sameId = idempotencyKey != null &&
          pending.idempotencyKey != null &&
          pending.idempotencyKey == idempotencyKey;
      final sameContent = pending.content == content;
      if (sameId || sameContent) {
        _pendingUserEchoes.removeAt(i);
        return true;
      }
    }
    return false;
  }

  void _capEntries() {
    if (entries.length > maxEntries) {
      entries.removeRange(0, entries.length - maxEntries);
    }
  }

  void _seedLastCanvasSurface(List<dynamic> messages) {
    for (int i = messages.length - 1; i >= 0; i--) {
      final msg = messages[i];
      if (msg is! Map<String, dynamic>) continue;
      final role = msg['role'] as String?;
      if (role != 'tool' && role != 'toolResult') continue;
      final contentList = msg['content'];
      if (contentList is! List) continue;
      for (final block in contentList) {
        if (block is! Map<String, dynamic>) continue;
        final text = block['text'] as String?;
        if (text != null && text.contains('__A2UI__')) {
          final payload = extractA2UIText(text);
          if (payload == null) continue;
          lastCanvasSurface = payload;
          pendingA2UIPayloads.add(payload);
          return;
        }
      }
    }
  }

  // -----------------------------------------------------------------------
  // Static extraction utilities
  // -----------------------------------------------------------------------

  /// Extract displayable text from a message content field.
  /// Handles both flat String content and the List<block> format.
  static String extractContent(dynamic rawContent) {
    if (rawContent is String) return rawContent;
    if (rawContent is List) {
      final textParts = <String>[];
      for (final block in rawContent) {
        if (block is! Map<String, dynamic>) continue;
        final type = block['type'] as String?;
        if (type == 'text') {
          final text = block['text'] as String? ?? '';
          if (text.isNotEmpty) textParts.add(text);
        }
      }
      return textParts.join('\n').trim();
    }
    return '';
  }

  /// Extract image attachments from history content blocks.
  static List<Map<String, dynamic>> extractImageAttachments(
      dynamic rawContent) {
    if (rawContent is! List) return const [];
    final attachments = <Map<String, dynamic>>[];
    for (final block in rawContent) {
      if (block is! Map<String, dynamic>) continue;
      final type = block['type'] as String?;
      if (type == 'image_url') {
        final imageUrl = block['image_url'];
        if (imageUrl is Map<String, dynamic>) {
          final url = imageUrl['url'] as String? ?? '';
          final match =
              RegExp(r'^data:(image/[^;]+);base64,(.+)$').firstMatch(url);
          if (match != null) {
            attachments.add({
              'content': match.group(2)!,
              'mimeType': match.group(1)!,
              'fileName': 'image',
              'type': 'image',
            });
          }
        }
      }
    }
    return attachments;
  }

  /// Extract A2UI payload from tool result text.
  static String? extractA2UIText(String raw) {
    final markerIndex = raw.indexOf('__A2UI__');
    if (markerIndex < 0) return null;
    return raw.substring(markerIndex);
  }

  /// Extract MEDIA: token paths from tool output.
  static final _mediaTokenExtractRe = RegExp(
    r'MEDIA:\s*(.+)',
    caseSensitive: false,
    multiLine: true,
  );
  static const _workspacePrefix = '/home/node/.openclaw/workspace/';
  static const _imageExts = {
    '.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg', '.bmp', '.tiff', '.tif'
  };
  static const Map<String, String> _mimeByExt = {
    '.pdf': 'application/pdf',
    '.doc': 'application/msword',
    '.docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    '.txt': 'text/plain',
    '.md': 'text/markdown',
    '.json': 'application/json',
    '.csv': 'text/csv',
    '.xml': 'application/xml',
    '.drawio': 'application/xml',
    '.xlsx':
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    '.xls': 'application/vnd.ms-excel',
    '.pptx':
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    '.ppt': 'application/vnd.ms-powerpoint',
    '.zip': 'application/zip',
  };

  static bool _isImagePath(String path) {
    final lower = path.toLowerCase();
    return _imageExts.any((ext) => lower.endsWith(ext));
  }

  static String _guessMimeType(String path) {
    final lower = path.toLowerCase();
    for (final entry in _mimeByExt.entries) {
      if (lower.endsWith(entry.key)) return entry.value;
    }
    if (_isImagePath(path)) {
      final ext = lower.contains('.')
          ? lower.substring(lower.lastIndexOf('.') + 1)
          : 'png';
      return 'image/$ext';
    }
    return 'application/octet-stream';
  }

  static List<Map<String, dynamic>> extractMediaArtifacts(String text) {
    if (text.isEmpty) return const [];
    final artifacts = <Map<String, dynamic>>[];
    for (final match in _mediaTokenExtractRe.allMatches(text)) {
      var raw = match.group(1)?.trim() ?? '';
      while (raw.isNotEmpty &&
          (raw[0] == '`' || raw[0] == '"' || raw[0] == "'")) {
        raw = raw.substring(1);
      }
      while (raw.isNotEmpty &&
          (raw[raw.length - 1] == '`' ||
              raw[raw.length - 1] == '"' ||
              raw[raw.length - 1] == "'")) {
        raw = raw.substring(0, raw.length - 1);
      }
      raw = raw.trim();
      if (raw.isEmpty) continue;
      String relative;
      if (raw.startsWith(_workspacePrefix)) {
        relative = raw.substring(_workspacePrefix.length);
      } else if (raw.startsWith('/')) {
        continue;
      } else {
        relative = raw;
      }
      if (relative.startsWith('media/')) {
        relative = relative.substring('media/'.length);
      }
      final fileName = relative.contains('/')
          ? relative.substring(relative.lastIndexOf('/') + 1)
          : relative;
      artifacts.add({
        'url': '/__openclaw__/media/$relative',
        'fileName': fileName,
        'mimeType': _guessMimeType(relative),
        'isImage': _isImagePath(relative),
      });
    }
    return artifacts;
  }
}

/// Tracks a user message that was optimistically echoed locally.
class PendingUserEcho {
  final String content;
  final String? idempotencyKey;
  final DateTime createdAt;

  const PendingUserEcho({
    required this.content,
    required this.idempotencyKey,
    required this.createdAt,
  });
}
