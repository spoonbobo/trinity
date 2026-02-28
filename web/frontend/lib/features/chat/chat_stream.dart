import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/gateway_client.dart' as gw;
import '../../models/ws_frame.dart';
import '../shell/shell_page.dart';

/// A single entry in the chat stream.
class ChatEntry {
  final String role; // 'user', 'assistant', 'tool', 'system'
  final String content;
  final String? toolName;
  final bool isStreaming;
  final DateTime timestamp;

  ChatEntry({
    required this.role,
    required this.content,
    this.toolName,
    this.isStreaming = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  ChatEntry copyWith({String? content, bool? isStreaming}) => ChatEntry(
        role: role,
        content: content ?? this.content,
        toolName: toolName,
        isStreaming: isStreaming ?? this.isStreaming,
        timestamp: timestamp,
      );
}

class ChatStreamView extends ConsumerStatefulWidget {
  const ChatStreamView({super.key});

  @override
  ConsumerState<ChatStreamView> createState() => _ChatStreamViewState();
}

class _ChatStreamViewState extends ConsumerState<ChatStreamView> {
  final List<ChatEntry> _entries = [];
  final _scrollController = ScrollController();
  StreamSubscription<WsEvent>? _chatSub;
  bool _agentThinking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _subscribeToChatEvents();
    });
  }

  void _subscribeToChatEvents() {
    final client = ref.read(gatewayClientProvider);

    // Listen for user messages sent through the prompt bar
    client.addListener(_onClientChange);

    _chatSub = client.chatEvents.listen((event) {
      _handleChatEvent(event);
    });
  }

  void _onClientChange() {
    // Re-subscribe if reconnected
    if (ref.read(gatewayClientProvider).state == gw.ConnectionState.connected) {
      _loadHistory();
    }
  }

  Future<void> _loadHistory() async {
    final client = ref.read(gatewayClientProvider);
    try {
      final response = await client.getChatHistory(limit: 50);
      if (response.ok && response.payload != null) {
        final messages = response.payload!['messages'] as List<dynamic>?;
        if (messages != null) {
          setState(() {
            _entries.clear();
            for (final msg in messages) {
              final m = msg as Map<String, dynamic>;
              _entries.add(ChatEntry(
                role: m['role'] as String? ?? 'system',
                content: m['content'] as String? ?? '',
              ));
            }
          });
          _scrollToBottom();
        }
      }
    } catch (_) {
      // History fetch may fail on first connect before any messages exist
    }
  }

  void _handleChatEvent(WsEvent event) {
    final payload = event.payload;

    if (event.event == 'chat') {
      final state = payload['state'] as String?;
      final type = payload['type'] as String?;

      if (type == 'message' && payload['role'] == 'user') {
        final content = payload['content'] as String? ?? '';
        setState(() {
          _entries.add(ChatEntry(role: 'user', content: content));
        });
      } else if (state == 'delta' || state == 'final') {
        final message = payload['message'] as Map<String, dynamic>?;
        if (message != null) {
          final contentList = message['content'] as List<dynamic>?;
          if (contentList != null && contentList.isNotEmpty) {
            final first = contentList[0] as Map<String, dynamic>;
            final text = first['text'] as String? ?? '';
            if (state == 'final') {
              setState(() {
                _agentThinking = false;
                if (_entries.isNotEmpty && _entries.last.role == 'assistant') {
                  _entries[_entries.length - 1] = _entries.last.copyWith(
                    content: text,
                    isStreaming: false,
                  );
                } else {
                  _entries.add(ChatEntry(role: 'assistant', content: text));
                }
              });
            } else {
              setState(() {
                _agentThinking = false;
                if (_entries.isNotEmpty &&
                    _entries.last.role == 'assistant' &&
                    _entries.last.isStreaming) {
                  _entries[_entries.length - 1] = _entries.last.copyWith(
                    content: text,
                    isStreaming: true,
                  );
                } else {
                  _entries.add(ChatEntry(
                    role: 'assistant',
                    content: text,
                    isStreaming: true,
                  ));
                }
              });
            }
          }
        }
      }
    } else if (event.event == 'agent') {
      final stream = payload['stream'] as String?;
      final data = payload['data'] as Map<String, dynamic>?;

      if (stream == 'lifecycle') {
        final phase = data?['phase'] as String?;
        if (phase == 'start') {
          setState(() => _agentThinking = true);
        } else if (phase == 'end') {
          setState(() {
            _agentThinking = false;
            if (_entries.isNotEmpty && _entries.last.role == 'assistant') {
              _entries[_entries.length - 1] =
                  _entries.last.copyWith(isStreaming: false);
            }
          });
        }
      } else if (stream == 'tool_call') {
        final toolName = data?['tool'] as String? ??
            data?['name'] as String? ??
            'tool';
        final args = data?['args']?.toString() ?? '';
        setState(() {
          _entries.add(ChatEntry(
            role: 'tool',
            content: args,
            toolName: toolName,
            isStreaming: true,
          ));
        });
      } else if (stream == 'tool_result') {
        final result = data?['result']?.toString() ??
            data?['output']?.toString() ??
            '';
        setState(() {
          if (_entries.isNotEmpty && _entries.last.role == 'tool') {
            _entries[_entries.length - 1] = _entries.last.copyWith(
              content: result,
              isStreaming: false,
            );
          }
        });
      }
    }

    _scrollToBottom();
  }

  void _appendAssistantContent(String content, {bool streaming = false}) {
    setState(() {
      _agentThinking = false;
      if (_entries.isNotEmpty &&
          _entries.last.role == 'assistant' &&
          _entries.last.isStreaming) {
        _entries[_entries.length - 1] = _entries.last.copyWith(
          content: _entries.last.content + content,
          isStreaming: streaming,
        );
      } else {
        _entries.add(ChatEntry(
          role: 'assistant',
          content: content,
          isStreaming: streaming,
        ));
      }
    });
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

  @override
  void dispose() {
    _chatSub?.cancel();
    ref.read(gatewayClientProvider).removeListener(_onClientChange);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_entries.isEmpty && !_agentThinking) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.terminal_rounded,
              size: 48,
              color: theme.colorScheme.primary.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'UNIVERSAL COMMAND CENTER',
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 3,
                color: const Color(0xFF3A3A3A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start typing or use voice to interact with the agent.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF4A4A4A),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _entries.length + (_agentThinking ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _entries.length && _agentThinking) {
          return _buildThinkingIndicator(theme);
        }
        return _buildEntry(_entries[index], theme);
      },
    );
  }

  Widget _buildEntry(ChatEntry entry, ThemeData theme) {
    switch (entry.role) {
      case 'user':
        return _UserBubble(entry: entry);
      case 'assistant':
        return _AssistantBubble(entry: entry);
      case 'tool':
        return _ToolCard(entry: entry);
      default:
        return _SystemMessage(entry: entry);
    }
  }

  Widget _buildThinkingIndicator(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary.withOpacity(0.5),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Thinking...',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF6B6B6B),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  final ChatEntry entry;
  const _UserBubble({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.65,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2A4A2A)),
        ),
        child: SelectableText(
          entry.content,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  final ChatEntry entry;
  const _AssistantBubble({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2A2A2A)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SelectableText(
                entry.content,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            if (entry.isStreaming)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: SizedBox(
                  width: 8,
                  height: 14,
                  child: _CursorBlink(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CursorBlink extends StatefulWidget {
  @override
  State<_CursorBlink> createState() => _CursorBlinkState();
}

class _CursorBlinkState extends State<_CursorBlink>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _opacity = _controller.drive(Tween(begin: 0.0, end: 1.0));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: 2,
        height: 14,
        color: const Color(0xFF6EE7B7),
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  final ChatEntry entry;
  const _ToolCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1520),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1E3A5F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                entry.isStreaming
                    ? Icons.hourglass_top_rounded
                    : Icons.check_circle_outline_rounded,
                size: 14,
                color: entry.isStreaming
                    ? const Color(0xFFFBBF24)
                    : const Color(0xFF6EE7B7),
              ),
              const SizedBox(width: 6),
              Text(
                entry.toolName ?? 'tool',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: const Color(0xFF3B82F6),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (entry.content.isNotEmpty) ...[
            const SizedBox(height: 6),
            SelectableText(
              entry.content.length > 500
                  ? '${entry.content.substring(0, 500)}...'
                  : entry.content,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 11,
                color: const Color(0xFF8B8B8B),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SystemMessage extends StatelessWidget {
  final ChatEntry entry;
  const _SystemMessage({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        entry.content,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF4A4A4A),
              fontStyle: FontStyle.italic,
            ),
      ),
    );
  }
}
