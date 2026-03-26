import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/gateway_client.dart' as gw;
import '../../models/ws_frame.dart';
import '../../core/providers.dart';

export 'chat_entry.dart';
import 'chat_entry.dart';
import 'chat_stream_processor.dart';

String _formatTimestamp(DateTime ts) {
  final h = ts.hour.toString().padLeft(2, '0');
  final m = ts.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

void _openHrefInBrowser(String href) {
  if (href.isEmpty) return;
  try {
    html.window.open(href, '_blank');
  } catch (_) {
    Clipboard.setData(ClipboardData(text: href));
  }
}

String _resolveMediaHref(String href, {String? authToken, String? openclawId}) {
  var base = href.replaceFirst('/__openclaw__/media/media/', '/__openclaw__/media/');
  if (!base.startsWith('/__openclaw__/media/')) return base;
  final uri = Uri.parse(base);
  final qp = Map<String, String>.from(uri.queryParameters);
  if (!qp.containsKey('openclaw') && (openclawId?.isNotEmpty ?? false)) {
    qp['openclaw'] = openclawId!;
  }
  if (!qp.containsKey('token') && (authToken?.isNotEmpty ?? false)) {
    qp['token'] = authToken!;
  }
  return uri.replace(queryParameters: qp.isEmpty ? null : qp).toString();
}

// ChatEntry is now in chat_entry.dart (re-exported above)

// (metadataSummary, metadataDetail, parseToolMetadata, parseToolMetadataDynamic
//  are now in chat_entry.dart)

class ChatStreamView extends ConsumerStatefulWidget {
  const ChatStreamView({super.key});

  @override
  ConsumerState<ChatStreamView> createState() => _ChatStreamViewState();
}

class _ChatStreamViewState extends ConsumerState<ChatStreamView> {
  final _processor = ChatStreamProcessor();
  final _scrollController = ScrollController();
  StreamSubscription<WsEvent>? _chatSub;
  bool _showScrollToBottom = false;
  String _currentSession = 'main';
  bool _historyLoading = false; // Guard against concurrent history fetches
  int _lastRefreshTick = 0;
  bool _disposed = false;
  gw.GatewayClient? _cachedClient; // Stored at subscribe time to avoid ref after dispose

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _subscribeToChatEvents();
    });
  }

  void _onScrollPositionChanged() {
    if (_disposed) return;
    final shouldShow = !_isNearBottom && _processor.entries.isNotEmpty;
    if (shouldShow != _showScrollToBottom) {
      setState(() => _showScrollToBottom = shouldShow);
    }
  }

  void _subscribeToChatEvents() {
    if (_disposed) return;
    _scrollController.addListener(_onScrollPositionChanged);
    final client = ref.read(gatewayClientProvider);
    _cachedClient = client;

    // Listen for user messages sent through the prompt bar
    client.addListener(_onClientChange);

    _chatSub = client.chatEvents.listen((event) {
      if (!_disposed) _handleChatEvent(event);
    });

    // If the gateway is already connected (e.g. listener registered after
    // the hello-ok notification fired), load history immediately.
    if (client.state == gw.ConnectionState.connected) {
      _loadHistory();
    }
  }

  void _onClientChange() {
    if (_disposed) return;
    // Re-subscribe if reconnected; guard prevents overlapping fetches.
    if (!_historyLoading &&
        _cachedClient?.state == gw.ConnectionState.connected) {
      _loadHistory();
    }
  }

  Future<void> _loadHistory() async {
    if (_historyLoading || _disposed) return; // Prevent concurrent fetches
    _historyLoading = true;
    final client = _cachedClient ?? (_disposed ? null : ref.read(gatewayClientProvider));
    if (client == null) { _historyLoading = false; return; }
    final sessionKey = _disposed ? _currentSession : ref.read(activeSessionProvider);
    try {
      final response = await client.getChatHistory(sessionKey: sessionKey, limit: 50);
      if (!mounted) { _historyLoading = false; return; }
      if (response.ok && response.payload != null) {
        final messages = response.payload?['messages']
            ?? response.payload?['history']
            ?? response.payload?['entries'];
        if (messages is List) {
          setState(() {
            _processor.loadHistory(messages);
          });
          // Render any A2UI surfaces found in history
          for (final payload in _processor.pendingA2UIPayloads) {
            _handleA2UIToolResult(payload);
          }
          _processor.pendingA2UIPayloads.clear();
          _jumpToBottomAfterLayout();
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Chat] _loadHistory error: $e');
    } finally {
      _historyLoading = false;
    }
  }

  // Static helpers and event processing logic are now in ChatStreamProcessor.

  void _handleChatEvent(WsEvent event) {
    try {
      // Detect lifecycle:end so we can poll for canvas surfaces once.
      final isLifecycleEnd = event.event == 'agent' &&
          (event.payload['stream'] as String?) == 'lifecycle' &&
          ((event.payload['data'] as Map<String, dynamic>?)?['phase']) == 'end';

      final changed = _processor.processEvent(event);
      // Handle A2UI events emitted by processor
      for (final payload in _processor.pendingA2UIPayloads) {
        _handleA2UIToolResult(payload);
      }
      _processor.pendingA2UIPayloads.clear();
      // Poll for canvas surface ONCE when the run ends, if tool calls happened.
      if (isLifecycleEnd && _processor.currentRunHadToolGap) {
        _pollCanvasSurface();
      }
      if (changed) setState(() {});
    } catch (e, st) {
      if (kDebugMode) debugPrint('[Chat] error handling event: $e\n$st');
    }
    _smartScrollToBottom();
  }

  Future<void> _pollCanvasSurface() async {
    if (_disposed) return;
    try {
      final gw.GatewayClient client = _cachedClient ?? ref.read(gatewayClientProvider);
      final sessionKey = ref.read(activeSessionProvider);
      final response = await client.getChatHistory(sessionKey: sessionKey, limit: 10);
      if (!response.ok || response.payload == null) return;
      final messages = response.payload!['messages'];
      if (messages is! List) return;

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
            final payload = ChatStreamProcessor.extractA2UIText(text);
            if (payload == null || payload == _processor.lastCanvasSurface) {
              continue;
            }
            _processor.lastCanvasSurface = payload;
            if (kDebugMode) debugPrint('[Canvas] Found A2UI in history, rendering surface');
            _handleA2UIToolResult(payload);
            // Only add a "Canvas updated" card if one doesn't already
            // exist in the current turn (the processor may have already
            // created one from the streaming tool_result event).
            setState(() {
              final entries = _processor.entries;
              bool alreadyHasCanvasCard = false;
              for (int i = entries.length - 1; i >= 0; i--) {
                if (entries[i].role == 'user') break;
                if (entries[i].role == 'tool' &&
                    entries[i].toolName == 'canvas_ui' &&
                    entries[i].content == 'Canvas updated') {
                  alreadyHasCanvasCard = true;
                  break;
                }
              }
              if (!alreadyHasCanvasCard) {
                entries.add(ChatEntry(
                  role: 'tool',
                  content: 'Canvas updated',
                  toolName: 'canvas_ui',
                  isStreaming: false,
                ));
              }
            });
            _scrollToBottom();
            return;
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Canvas] poll error: $e');
    }
  }

  void _handleA2UIToolResult(String result) {
    if (_disposed) return;
    final lines = result.split('\n').skip(1);
    final client = _cachedClient ?? (_disposed ? null : ref.read(gatewayClientProvider));
    if (client == null) return;
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final parsed = jsonDecode(line.trim()) as Map<String, dynamic>;
        client.emitCanvasEvent(WsEvent(event: 'a2ui', payload: parsed));
      } catch (e) {
        if (kDebugMode) debugPrint('[A2UI] Failed to parse JSONL line: $e');
      }
    }
  }

  // #11: Smart scroll -- only auto-scroll if user is near the bottom
  bool get _isNearBottom {
    if (!_scrollController.hasClients) return true;
    final pos = _scrollController.position;
    return pos.maxScrollExtent - pos.pixels < 100;
  }

  void _smartScrollToBottom() {
    if (!_isNearBottom) return;
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Jump to bottom without animation -- used after history load where the
  /// ListView content may settle across multiple frames (markdown rendering,
  /// image placeholders, font loading). Two post-frame passes ensure we
  /// catch late layout shifts.
  void _jumpToBottomAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      // Second pass: catch any remaining layout shifts from async content
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _chatSub?.cancel();
    _cachedClient?.removeListener(_onClientChange);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = ShellTokens.of(context);

    // Reload history when session changes
    final sessionKey = ref.watch(activeSessionProvider);
    if (sessionKey != _currentSession) {
      _currentSession = sessionKey;
      _processor.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadHistory());
    }

    final refreshTick = ref.watch(chatRefreshTickProvider);
    if (refreshTick != _lastRefreshTick) {
      _lastRefreshTick = refreshTick;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadHistory());
    }

    // #14 (chat): Better empty state with hint
    if (_processor.entries.isEmpty && !_processor.agentThinking) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: kShellBorderRadius,
                border: Border.all(color: t.border, width: 0.5),
              ),
              child: Icon(Icons.chat_outlined, size: 16, color: t.fgMuted),
            ),
            const SizedBox(height: 10),
            Text('start a conversation',
              style: TextStyle(fontSize: 11, color: t.fgMuted, letterSpacing: 0.5)),
            const SizedBox(height: 4),
            Text('type a message below',
              style: TextStyle(fontSize: 10, color: t.fgPlaceholder)),
          ],
        ),
      );
    }

    // (F) Stack with floating scroll-to-bottom button
    // SizeChangedLayoutNotifier fires when the viewport size changes
    // (e.g., PromptBar height changes from attachments, multi-line text, voice).
    // This keeps the chat pinned to the bottom when the user was already there.
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _smartScrollToBottom();
        return false;
      },
      child: SizeChangedLayoutNotifier(
      child: Stack(
      children: [
        ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: _processor.entries.length + (_processor.agentThinking ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == _processor.entries.length && _processor.agentThinking) {
              return _buildThinkingIndicator(theme);
            }
            final entry = _processor.entries[index];
            final prev = index > 0 ? _processor.entries[index - 1] : null;
            final isNewSender = prev == null || prev.role != entry.role;
            return _buildEntry(entry, theme, isNewSender: isNewSender);
          },
        ),
        if (_showScrollToBottom)
          Positioned(
            right: 12,
            bottom: 8,
            child: GestureDetector(
              onTap: () {
                _scrollToBottom();
                setState(() => _showScrollToBottom = false);
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    borderRadius: kShellBorderRadius,
                    color: t.surfaceCard,
                    border: Border.all(color: t.border, width: 0.5),
                  ),
                  child: Icon(Icons.keyboard_arrow_down,
                    size: 16, color: t.fgMuted),
                ),
              ),
            ),
          ),
      ],
    ),
      ),
    );
  }

  Widget _buildEntry(ChatEntry entry, ThemeData theme, {bool isNewSender = true}) {
    switch (entry.role) {
      case 'user':
        return _UserBubble(entry: entry, isNewSender: isNewSender);
      case 'assistant':
        // Skip empty assistant entries (tool-call-only turns with no text)
        if (entry.content.isEmpty && !entry.isStreaming) {
          return const SizedBox.shrink();
        }
        final authState = ref.read(authClientProvider).state;
        return _AssistantBubble(
          entry: entry,
          isNewSender: isNewSender,
          authToken: authState.token,
          openclawId: authState.activeOpenClawId,
        );
      case 'tool':
        return _ToolCard(entry: entry);
      default:
        return _SystemMessage(entry: entry);
    }
  }

  Widget _buildThinkingIndicator(ThemeData theme) {
    final t = ShellTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4, right: 80),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: kShellBorderRadius,
              color: t.surfaceCard,
              border: Border.all(color: t.border, width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _StreamingIndicator(),
                const SizedBox(width: 8),
                Text(
                  'thinking',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: t.fgTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// PendingUserEcho is now in chat_stream_processor.dart

class _UserBubble extends StatefulWidget {
  final ChatEntry entry;
  final bool isNewSender;
  const _UserBubble({required this.entry, this.isNewSender = true});

  @override
  State<_UserBubble> createState() => _UserBubbleState();
}

class _UserBubbleState extends State<_UserBubble> {
  bool _hovering = false;
  bool _copied = false;

  /// Memoized decoded image bytes to avoid re-decoding base64 on every rebuild.
  /// Key: attachment index, Value: decoded Uint8List.
  late final Map<int, Uint8List> _decodedImages = _decodeImageAttachments();

  Map<int, Uint8List> _decodeImageAttachments() {
    final result = <int, Uint8List>{};
    final attachments = widget.entry.attachments;
    if (attachments == null) return result;
    for (int i = 0; i < attachments.length; i++) {
      final a = attachments[i];
      final mime = a['mimeType'] as String? ?? '';
      // Support both OpenClaw field name (content) and legacy (base64)
      final b64 = a['content'] as String? ?? a['base64'] as String?;
      if (mime.startsWith('image/') && b64 != null) {
        try {
          result[i] = base64Decode(b64);
        } catch (_) {
          // Skip invalid base64
        }
      }
    }
    return result;
  }

  void _copyMessage() {
    Clipboard.setData(ClipboardData(text: widget.entry.content)).then((_) {
      if (!mounted) return;
      setState(() => _copied = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = false);
      });
    }).catchError((_) {});
  }

  void _openHref(String href) {
    if (href.isEmpty) return;
    _openHrefInBrowser(_resolveMediaHref(href));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = ShellTokens.of(context);
    final baseStyle = theme.textTheme.bodyLarge ?? const TextStyle();
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Padding(
        padding: EdgeInsets.only(
          top: widget.isNewSender ? 14 : 3,
          bottom: 1,
          left: 80,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: kShellBorderRadius,
                  color: t.accentPrimary.withOpacity(0.08),
                  border: Border.all(color: t.accentPrimary.withOpacity(0.18), width: 0.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (widget.entry.attachments != null && widget.entry.attachments!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          alignment: WrapAlignment.end,
                          children: List.generate(widget.entry.attachments!.length, (i) {
                            final a = widget.entry.attachments![i];
                            final mime = a['mimeType'] as String? ?? '';
                            // Support both OpenClaw (fileName) and legacy (name) field names
                            final name = a['fileName'] as String? ?? a['name'] as String? ?? 'file';
                            final cachedBytes = _decodedImages[i];
                            if (cachedBytes != null) {
                              return Container(
                                constraints: const BoxConstraints(maxWidth: 180, maxHeight: 120),
                                decoration: BoxDecoration(
                                  borderRadius: kShellBorderRadiusSm,
                                  border: Border.all(color: t.border, width: 0.5),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Image.memory(
                                  cachedBytes,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                ),
                              );
                            }
                            // Pick icon based on file type
                            final ext = name.contains('.') ? name.substring(name.lastIndexOf('.')).toLowerCase() : '';
                            final IconData fileIcon;
                            if (mime.startsWith('audio/')) {
                              fileIcon = Icons.audiotrack;
                            } else if (mime.startsWith('video/')) {
                              fileIcon = Icons.videocam;
                            } else if (mime == 'application/pdf' || ext == '.pdf') {
                              fileIcon = Icons.picture_as_pdf;
                            } else if (const {'.docx', '.doc', '.odt', '.rtf'}.contains(ext) ||
                                       mime.contains('wordprocessingml') || mime == 'application/msword' ||
                                       mime.contains('opendocument.text') || mime == 'application/rtf') {
                              fileIcon = Icons.description;
                            } else if (const {'.xlsx', '.xls', '.ods', '.csv'}.contains(ext) ||
                                       mime.contains('spreadsheetml') || mime == 'application/vnd.ms-excel' ||
                                       mime.contains('opendocument.spreadsheet') || mime == 'text/csv') {
                              fileIcon = Icons.table_chart;
                            } else if (const {'.pptx', '.ppt', '.odp'}.contains(ext) ||
                                       mime.contains('presentationml') || mime == 'application/vnd.ms-powerpoint' ||
                                       mime.contains('opendocument.presentation')) {
                              fileIcon = Icons.slideshow;
                            } else if (mime == 'application/epub+zip' || ext == '.epub') {
                              fileIcon = Icons.menu_book;
                            } else if (const {'.py', '.js', '.ts', '.dart', '.java', '.c', '.cpp', '.go', '.rs', '.rb', '.php', '.kt', '.swift', '.lua', '.sh', '.bash', '.zsh'}.contains(ext) ||
                                       mime.startsWith('text/x-') || mime == 'text/javascript' || mime == 'text/typescript') {
                              fileIcon = Icons.code;
                            } else {
                              fileIcon = Icons.insert_drive_file;
                            }
                            final url = a['url'] as String?;
                            final resolvedUrl = (url == null || url.isEmpty)
                                ? null
                                : _resolveMediaHref(url);
                            final chip = Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                borderRadius: kShellBorderRadiusSm,
                                color: t.surfaceCard,
                                border: Border.all(
                                  color: resolvedUrl != null ? t.accentPrimaryMuted : t.border,
                                  width: 0.5,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    fileIcon,
                                    size: 10,
                                    color: resolvedUrl != null ? t.accentPrimary : t.fgMuted,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(name,
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: resolvedUrl != null ? t.accentPrimary : t.fgTertiary,
                                      decoration: resolvedUrl != null
                                          ? TextDecoration.underline
                                          : TextDecoration.none,
                                    )),
                                ],
                              ),
                            );
                            if (resolvedUrl == null) return chip;
                            return GestureDetector(
                              onTap: () => _openHref(resolvedUrl),
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: chip,
                              ),
                            );
                          }),
                        ),
                      ),
                    if (widget.entry.content.isNotEmpty && widget.entry.content != '[attachment]')
                      SelectionArea(
                        child: MarkdownBody(
                          data: widget.entry.content,
                          selectable: false,
                          styleSheet: MarkdownStyleSheet(
                            p: baseStyle.copyWith(color: t.fgPrimary),
                            code: baseStyle.copyWith(fontSize: 13, color: t.accentPrimary, backgroundColor: t.surfaceCodeInline),
                            codeblockDecoration: BoxDecoration(
                              borderRadius: kShellBorderRadiusSm,
                              color: t.surfaceBase,
                              border: Border(left: BorderSide(color: t.border, width: 2)),
                            ),
                            codeblockPadding: const EdgeInsets.only(left: 12, top: 8, bottom: 8, right: 8),
                            strong: baseStyle.copyWith(fontWeight: FontWeight.bold, color: t.fgPrimary),
                            em: baseStyle.copyWith(fontStyle: FontStyle.italic, color: t.fgPrimary),
                            a: baseStyle.copyWith(
                              color: t.accentPrimary,
                              decoration: TextDecoration.underline,
                              decorationColor: t.accentPrimaryMuted,
                            ),
                          ),
                          onTapLink: (text, href, title) {
                            if (href != null) {
                              _openHref(href);
                            }
                          },
                        ),
                      ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_hovering)
                          GestureDetector(
                            onTap: _copyMessage,
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _copied ? Icons.check : Icons.copy,
                                      size: 12,
                                      color: _copied ? t.accentPrimary : t.fgMuted,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _copied ? 'copied' : 'copy',
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: _copied ? t.accentPrimary : t.fgMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        Text(
                          _formatTimestamp(widget.entry.timestamp),
                          style: TextStyle(fontSize: 9, color: t.fgMuted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssistantBubble extends StatefulWidget {
  final ChatEntry entry;
  final bool isNewSender;
  final String? authToken;
  final String? openclawId;
  const _AssistantBubble({
    required this.entry,
    this.isNewSender = true,
    this.authToken,
    this.openclawId,
  });

  @override
  State<_AssistantBubble> createState() => _AssistantBubbleState();
}

class _AssistantBubbleState extends State<_AssistantBubble> {
  bool _hovering = false;
  bool _copied = false;

  void _openHref(String href) {
    if (href.isEmpty) return;
    _openHrefInBrowser(
      _resolveMediaHref(href, authToken: widget.authToken, openclawId: widget.openclawId),
    );
  }

  /// Image file extensions used for detection.
  static const _imgExts = r'\.(?:png|jpe?g|gif|webp|svg|bmp|tiff?)';
  static final _imgExtsRe = RegExp(_imgExts + r'$', caseSensitive: false);
  static final _nonImageWorkspacePathRe = RegExp(
    r'(?<!\]\()' // not preceded by ](
    r'/home/node/\.openclaw/workspace/([^\s)\]`]+)',
    caseSensitive: false,
  );
  static final _nonImageMediaUrlRe = RegExp(
    r'(?<!\]\()' // not preceded by ](
    r'(/__openclaw__/media/[^\s)\]`]+)',
    caseSensitive: false,
  );

  /// 1. Bare /__openclaw__/media/ URLs not already inside markdown image syntax.
  static final _mediaUrlRe = RegExp(
    r'(?<!\]\()' // not preceded by ](
    r'(/__openclaw__/media/[^\s)\]`]+' + _imgExts + ')',
    caseSensitive: false,
  );

  /// 2. Absolute workspace paths:
  ///    /home/node/.openclaw/workspace/<relative-path>.png
  static final _backtickedAbsWorkspaceRe = RegExp(
    r'`/home/node/\.openclaw/workspace/([^`\s)\]]+' + _imgExts + r')`',
    caseSensitive: false,
  );
  static final _backtickedNonImageWorkspaceRe = RegExp(
    r'`/home/node/\.openclaw/workspace/([^`\s)\]]+)`',
    caseSensitive: false,
  );
  static final _backtickedNonImageMediaUrlRe = RegExp(
    r'`(/__openclaw__/media/[^`\s)\]]+)`',
    caseSensitive: false,
  );

  static final _absWorkspaceRe = RegExp(
    r'(?<!\]\()' // not preceded by ](
    r'/home/node/\.openclaw/workspace/([^\s)\]`]+' + _imgExts + ')',
    caseSensitive: false,
  );

  /// 3. MEDIA: token lines (in case gateway didn't strip them).
  static final _mediaTokenRe = RegExp(
    r'MEDIA:\s*([^\s]+' + _imgExts + ')',
    caseSensitive: false,
  );

  static final _mediaFileTokenRe = RegExp(
    r'MEDIA:\s*([^\s)\]`]+)',
    caseSensitive: false,
  );

  /// Pre-process assistant content to ensure workspace images render inline.
  ///
  /// Converts three patterns into markdown ![image](url):
  ///   - /__openclaw__/media/<path>.png  (already correct URL)
  ///   - /home/node/.openclaw/workspace/<path>.png  (absolute -> media URL)
  ///   - MEDIA: <path>.png  (raw token -> media URL)
  ///
  /// Skips matches already inside markdown image syntax `](url)`.
  String _enrichContentWithImages(String content) {
    var result = content;

    String normalizeRelative(String input) {
      final trimmed = input.replaceFirst(RegExp(r'^/+'), '');
      return trimmed.startsWith('media/')
          ? trimmed.substring('media/'.length)
          : trimmed;
    }

    // Pass 0: Convert backticked absolute workspace paths to markdown images.
    // Without this, replacements can become `![image](...)` and render as code.
    result = result.replaceAllMapped(_backtickedAbsWorkspaceRe, (m) {
      final relative = normalizeRelative(m.group(1)!);
      return '![image](/__openclaw__/media/$relative)';
    });

    // Pass 0b: Convert backticked absolute workspace paths for non-image files.
    result = result.replaceAllMapped(_backtickedNonImageWorkspaceRe, (m) {
      final relativeRaw = m.group(1)!;
      if (_imgExtsRe.hasMatch(relativeRaw.toLowerCase())) return m.group(0)!;
      final relative = normalizeRelative(relativeRaw);
      final name = relative.contains('/') ? relative.substring(relative.lastIndexOf('/') + 1) : relative;
      return '[${name}](/__openclaw__/media/$relative)';
    });

    // Pass 0c: Convert backticked media URLs for non-image files.
    result = result.replaceAllMapped(_backtickedNonImageMediaUrlRe, (m) {
      final url = m.group(1)!;
      if (_imgExtsRe.hasMatch(url.toLowerCase())) return m.group(0)!;
      final name = url.contains('/') ? url.substring(url.lastIndexOf('/') + 1) : url;
      return '[$name]($url)';
    });

    // Pass 1: Convert absolute workspace paths to media URLs
    result = result.replaceAllMapped(_absWorkspaceRe, (m) {
      if (m.start > 0 && result[m.start - 1] == '(') return m.group(0)!;
      final relative = normalizeRelative(m.group(1)!);
      return '![image](/__openclaw__/media/$relative)';
    });

    // Pass 2: Convert MEDIA: tokens to media URLs
    result = result.replaceAllMapped(_mediaTokenRe, (m) {
      final raw = m.group(1)!;
      // Strip workspace prefix if present
      final relativeRaw = raw.startsWith('/home/node/.openclaw/workspace/')
          ? raw.substring('/home/node/.openclaw/workspace/'.length)
          : raw;
      final relative = normalizeRelative(relativeRaw);
      return '![image](/__openclaw__/media/$relative)';
    });

    // Pass 2b: Convert remaining MEDIA: tokens for non-image files to markdown links.
    result = result.replaceAllMapped(_mediaFileTokenRe, (m) {
      final raw = m.group(1)!;
      final lower = raw.toLowerCase();
      if (_imgExtsRe.hasMatch(lower)) return m.group(0)!;
      final relativeRaw = raw.startsWith('/home/node/.openclaw/workspace/')
          ? raw.substring('/home/node/.openclaw/workspace/'.length)
          : raw;
      if (relativeRaw.startsWith('/')) return m.group(0)!;
      final relative = normalizeRelative(relativeRaw);
      final name = relative.contains('/') ? relative.substring(relative.lastIndexOf('/') + 1) : relative;
      return '[Generated file: $name](/__openclaw__/media/$relative)';
    });

    // Pass 2c: Convert absolute workspace paths for non-image files to markdown links.
    result = result.replaceAllMapped(_nonImageWorkspacePathRe, (m) {
      if (m.start > 0 && result[m.start - 1] == '(') return m.group(0)!;
      final relativeRaw = m.group(1)!;
      if (_imgExtsRe.hasMatch(relativeRaw.toLowerCase())) return m.group(0)!;
      final relative = normalizeRelative(relativeRaw);
      final name = relative.contains('/') ? relative.substring(relative.lastIndexOf('/') + 1) : relative;
      return '[${name}](/__openclaw__/media/$relative)';
    });

    // Pass 3: Convert bare /__openclaw__/media/ URLs
    result = result.replaceAllMapped(_mediaUrlRe, (m) {
      if (m.start > 0 && result[m.start - 1] == '(') return m.group(0)!;
      final url = m.group(1)!;
      return '![image]($url)';
    });

    // Pass 4: Convert bare non-image media URLs to markdown links.
    result = result.replaceAllMapped(_nonImageMediaUrlRe, (m) {
      if (m.start > 0 && result[m.start - 1] == '(') return m.group(0)!;
      final url = m.group(1)!;
      if (_imgExtsRe.hasMatch(url.toLowerCase())) return m.group(0)!;
      final name = url.contains('/') ? url.substring(url.lastIndexOf('/') + 1) : url;
      return '[$name]($url)';
    });

    return result;
  }

  void _copyMessage() {
    Clipboard.setData(ClipboardData(text: widget.entry.content)).then((_) {
      if (!mounted) return;
      setState(() => _copied = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = false);
      });
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = ShellTokens.of(context);
    final baseStyle = theme.textTheme.bodyLarge ?? const TextStyle();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Padding(
        padding: EdgeInsets.only(
          top: widget.isNewSender ? 14 : 3,
          bottom: 1,
          right: 48,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.isNewSender)
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 2),
                child: Text(
                  'trinity',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: t.fgTertiary,
                    fontSize: 10,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: kShellBorderRadius,
                color: t.surfaceCard,
                border: Border.all(color: t.border, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectionArea(
                    child: MarkdownBody(
                      data: _enrichContentWithImages(widget.entry.content),
                      selectable: false,
                      styleSheet: MarkdownStyleSheet(
                        p: baseStyle,
                        h1: baseStyle.copyWith(fontSize: 16, fontWeight: FontWeight.bold, color: t.fgPrimary),
                        h2: baseStyle.copyWith(fontSize: 15, fontWeight: FontWeight.bold, color: t.fgPrimary),
                        h3: baseStyle.copyWith(fontSize: 14, fontWeight: FontWeight.bold),
                        code: baseStyle.copyWith(fontSize: 13, color: t.accentPrimary, backgroundColor: t.surfaceCodeInline),
                        codeblockDecoration: BoxDecoration(
                          borderRadius: kShellBorderRadiusSm,
                          color: t.surfaceBase,
                          border: Border(left: BorderSide(color: t.border, width: 2)),
                        ),
                        codeblockPadding: const EdgeInsets.only(left: 12, top: 8, bottom: 8, right: 8),
                        blockquoteDecoration: BoxDecoration(
                          borderRadius: kShellBorderRadiusSm,
                          border: Border(left: BorderSide(color: t.fgDisabled, width: 2)),
                        ),
                        blockquotePadding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
                        listBullet: baseStyle.copyWith(color: t.fgTertiary),
                        strong: baseStyle.copyWith(fontWeight: FontWeight.bold),
                        em: baseStyle.copyWith(fontStyle: FontStyle.italic),
                        a: baseStyle.copyWith(
                          color: t.accentPrimary,
                          decoration: TextDecoration.underline,
                          decorationColor: t.accentPrimaryMuted,
                        ),
                        tableHead: baseStyle.copyWith(fontWeight: FontWeight.bold),
                        tableBorder: TableBorder.all(color: t.border, width: 0.5),
                        tableHeadAlign: TextAlign.left,
                        tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        horizontalRuleDecoration: BoxDecoration(
                          border: Border(top: BorderSide(color: t.border, width: 0.5)),
                        ),
                      ),
                      imageBuilder: (uri, title, alt) {
                        return _ChatImage(
                          url: uri.toString(),
                          authToken: widget.authToken,
                          openclawId: widget.openclawId,
                        );
                      },
                      onTapLink: (text, href, title) {
                        if (href != null) {
                          _openHref(href);
                        }
                      },
                    ),
                  ),
                  if (widget.entry.isStreaming)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: _StreamingIndicator(),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        _formatTimestamp(widget.entry.timestamp),
                        style: TextStyle(fontSize: 9, color: t.fgMuted),
                      ),
                      const Spacer(),
                      if (_hovering && !widget.entry.isStreaming)
                        GestureDetector(
                          onTap: _copyMessage,
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _copied ? Icons.check : Icons.copy,
                                  size: 12,
                                  color: _copied ? t.accentPrimary : t.fgMuted,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _copied ? 'copied' : 'copy',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: _copied ? t.accentPrimary : t.fgMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StreamingIndicator extends StatefulWidget {
  const _StreamingIndicator();

  @override
  State<_StreamingIndicator> createState() => _StreamingIndicatorState();
}

class _StreamingIndicatorState extends State<_StreamingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final phase = _controller.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final offset = (phase - (index * 0.2)) % 1.0;
            final pulse = (1.0 - (offset - 0.5).abs() * 2.0).clamp(0.0, 1.0);
            final opacity = 0.25 + (pulse * 0.55);
            return Padding(
              padding: EdgeInsets.only(right: index == 2 ? 0 : 4),
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: t.accentPrimary.withOpacity(opacity),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// #12: Expandable tool output
class _ToolCard extends StatefulWidget {
  final ChatEntry entry;
  const _ToolCard({required this.entry});

  @override
  State<_ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<_ToolCard> {
  static const int _collapsedLimit = 300;
  static const int _expandedLimit = 1500;

  bool _expanded = false;

  /// Format elapsed duration as a compact string (e.g. "1.2s", "350ms").
  String _formatElapsed(Duration d) {
    if (d.inMilliseconds < 1000) return '${d.inMilliseconds}ms';
    final secs = d.inMilliseconds / 1000.0;
    if (secs < 60) return '${secs.toStringAsFixed(1)}s';
    final mins = d.inMinutes;
    final remSecs = (secs - mins * 60).toInt();
    return '${mins}m ${remSecs}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = ShellTokens.of(context);
    final toolName = widget.entry.toolName ?? 'tool';
    final summary = widget.entry.metadataSummary;
    final detail = widget.entry.metadataDetail;
    final isStreaming = widget.entry.isStreaming;
    final elapsed = widget.entry.elapsed;

    // Result content: only show when tool has completed (not streaming)
    // and only if there's no structured summary (avoid showing raw args)
    final rawContent = widget.entry.content;
    final resultContent = (!isStreaming && summary != null) ? rawContent : rawContent;
    final showResult = !isStreaming && resultContent.isNotEmpty;

    final canExpand = showResult && resultContent.length > _collapsedLimit;
    final hardCapped = showResult && resultContent.length > _expandedLimit;

    String displayResult = '';
    if (showResult) {
      if (!canExpand) {
        displayResult = resultContent;
      } else if (_expanded) {
        displayResult = hardCapped
            ? '${resultContent.substring(0, _expandedLimit)}... (truncated)'
            : resultContent;
      } else {
        displayResult = '${resultContent.substring(0, _collapsedLimit)}...';
      }
    }

    final showToggle = canExpand && !(_expanded && hardCapped);

    return Padding(
      padding: const EdgeInsets.only(top: 3, bottom: 3, right: 48),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: kShellBorderRadiusSm,
          color: t.surfaceBase,
          border: Border.all(color: t.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: [dots] toolName [elapsed]
            Row(
              children: [
                if (isStreaming) ...[
                  SizedBox(
                    width: 22,
                    height: 8,
                    child: const _StreamingIndicator(),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  toolName,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isStreaming ? t.accentPrimary : t.fgTertiary,
                    fontSize: 10,
                    letterSpacing: 0.3,
                  ),
                ),
                if (elapsed != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    _formatElapsed(elapsed),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: t.fgMuted,
                      fontSize: 9,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ],
            ),
            // Structured summary line (command, path, pattern)
            if (summary != null) ...[
              const SizedBox(height: 3),
              SelectableText(
                summary,
                maxLines: 2,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 11,
                  color: isStreaming ? t.fgSecondary : t.fgTertiary,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
            ],
            // Detail line (workdir, host, line range)
            if (detail != null) ...[
              const SizedBox(height: 1),
              Text(
                detail,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 9,
                  color: t.fgMuted,
                  letterSpacing: 0.2,
                ),
              ),
            ],
            // Result content (after completion)
            if (showResult && summary != null && displayResult.isNotEmpty) ...[
              const SizedBox(height: 4),
              SelectableText(
                displayResult,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 11,
                  color: t.fgTertiary,
                  height: 1.4,
                ),
              ),
            ] else if (showResult && summary == null && displayResult.isNotEmpty) ...[
              // No structured metadata -- fall back to raw content display
              const SizedBox(height: 4),
              SelectableText(
                displayResult,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 11,
                  color: t.fgTertiary,
                  height: 1.4,
                ),
              ),
            ] else if (isStreaming && summary == null && rawContent.isNotEmpty) ...[
              // Streaming with no parsed metadata -- show raw args
              const SizedBox(height: 4),
              SelectableText(
                rawContent.length > _collapsedLimit
                    ? '${rawContent.substring(0, _collapsedLimit)}...'
                    : rawContent,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 11,
                  color: t.fgTertiary,
                  height: 1.4,
                ),
              ),
            ],
            if (showToggle)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Text(
                      _expanded ? 'show less' : 'show more',
                      style: TextStyle(
                        fontSize: 10,
                        color: t.accentPrimary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SystemMessage extends StatelessWidget {
  final ChatEntry entry;
  const _SystemMessage({required this.entry});

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Text(
          entry.content,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: t.fgDisabled,
                fontSize: 11,
              ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// Rendered image in chat with hover-only copy/download toolbar.
class _ChatImage extends StatefulWidget {
  final String url;
  final String? authToken;
  final String? openclawId;
  const _ChatImage({required this.url, this.authToken, this.openclawId});

  @override
  State<_ChatImage> createState() => _ChatImageState();
}

class _ChatImageState extends State<_ChatImage> {
  bool _hovering = false;
  bool _copied = false;

  String get _resolvedUrl {
    return _resolveMediaHref(widget.url, authToken: widget.authToken, openclawId: widget.openclawId);
  }

  void _downloadImage() {
    final filename = _resolvedUrl.split('/').last.split('?').first;
    html.AnchorElement(href: _resolvedUrl)
      ..setAttribute('download', filename.isNotEmpty ? filename : 'image.png')
      ..click();
  }

  void _copyImageUrl() {
    Clipboard.setData(ClipboardData(text: _resolvedUrl)).then((_) {
      if (!mounted) return;
      setState(() => _copied = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = false);
      });
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Stack(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400, maxHeight: 300),
            child: Image.network(
              _resolvedUrl,
              fit: BoxFit.contain,
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return SizedBox(
                  height: 80,
                  child: Center(child: SizedBox(
                    width: 60,
                    child: LinearProgressIndicator(
                      value: progress.expectedTotalBytes != null
                        ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                        : null,
                      backgroundColor: t.border,
                      color: t.accentPrimary,
                      minHeight: 2,
                    ),
                  )),
                );
              },
              errorBuilder: (_, __, ___) => Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: kShellBorderRadiusSm,
                  color: t.surfaceBase,
                  border: Border.all(color: t.border, width: 0.5),
                ),
                child: Text('[image failed to load]',
                  style: TextStyle(fontSize: 11, color: t.fgMuted)),
              ),
            ),
          ),
          if (_hovering)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                decoration: BoxDecoration(
                  color: t.surfaceBase.withOpacity(0.85),
                  border: Border.all(color: t.border, width: 0.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: _copyImageUrl,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _copied ? Icons.check : Icons.copy,
                              size: 12,
                              color: _copied ? t.accentPrimary : t.fgMuted,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              _copied ? 'copied' : 'copy',
                              style: TextStyle(fontSize: 10, color: t.fgMuted),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(width: 0.5, height: 16, color: t.border),
                    GestureDetector(
                      onTap: _downloadImage,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.download, size: 12, color: t.fgMuted),
                            const SizedBox(width: 3),
                            Text(
                              'download',
                              style: TextStyle(fontSize: 10, color: t.fgMuted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
