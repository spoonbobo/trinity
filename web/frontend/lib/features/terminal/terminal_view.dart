import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/terminal_client.dart';

class TerminalView extends StatefulWidget {
  final TerminalProxyClient client;
  final bool showInput;
  final List<String> suggestedCommands;
  final VoidCallback? onCommandExecuted;

  const TerminalView({
    super.key,
    required this.client,
    this.showInput = true,
    this.suggestedCommands = const [],
    this.onCommandExecuted,
  });

  @override
  State<TerminalView> createState() => _TerminalViewState();
}

class _TerminalViewState extends State<TerminalView> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _commandController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.client.addListener(_onClientUpdate);
  }

  @override
  void dispose() {
    widget.client.removeListener(_onClientUpdate);
    _scrollController.dispose();
    _commandController.dispose();
    super.dispose();
  }

  void _onClientUpdate() {
    if (mounted) {
      setState(() {});
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 50), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _executeCommand(String command) {
    if (command.trim().isEmpty) return;
    widget.client.executeCommand(command.trim());
    _commandController.clear();
    widget.onCommandExecuted?.call();
  }

  Color _getOutputColor(String type) {
    final t = ShellTokens.of(context);
    switch (type) {
      case 'stdout':
        return t.fgPrimary;
      case 'stderr':
        return t.statusError;
      case 'system':
        return t.fgTertiary;
      case 'error':
        return t.statusError;
      case 'exit':
        return t.accentPrimary;
      default:
        return t.fgPrimary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = ShellTokens.of(context);

    return Column(
      children: [
        // Output
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(12),
            itemCount: widget.client.outputs.length,
            itemBuilder: (context, index) {
              final output = widget.client.outputs[index];
              return SelectableText(
                output.data ?? output.message ?? '',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 13,
                  color: _getOutputColor(output.type),
                  height: 1.5,
                ),
              );
            },
          ),
        ),
        // Suggested commands
        if (widget.suggestedCommands.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: t.border, width: 0.5),
              ),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: widget.suggestedCommands.map((cmd) {
                return GestureDetector(
                  onTap: () => _executeCommand(cmd),
                  child: Text(
                    cmd,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: t.fgMuted,
                      fontSize: 12,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        // Input
        if (widget.showInput)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: t.border, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                Text(
                  '> ',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: widget.client.isConnected
                        ? t.accentPrimary
                        : t.fgDisabled,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _commandController,
                    enabled: widget.client.isConnected && !widget.client.isExecuting,
                    style: theme.textTheme.bodyLarge?.copyWith(color: t.fgPrimary),
                    decoration: const InputDecoration(
                      hintText: '',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                    onSubmitted: _executeCommand,
                  ),
                ),
                if (widget.client.isExecuting)
                  GestureDetector(
                    onTap: widget.client.cancelCommand,
                    child: Text(
                      'cancel',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: t.statusError,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
