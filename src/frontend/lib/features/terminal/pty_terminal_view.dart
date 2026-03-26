import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../core/providers.dart';
import '../../core/terminal_client.dart';
import '../../core/theme.dart';

class PtyTerminalView extends ConsumerStatefulWidget {
  final TerminalProxyClient client;
  final List<String> suggestedCommands;
  final String? initialCommand;
  final int cols;
  final int rows;
  final bool showHeader;

  const PtyTerminalView({
    super.key,
    required this.client,
    this.suggestedCommands = const [],
    this.initialCommand,
    this.cols = 120,
    this.rows = 32,
    this.showHeader = true,
  });

  @override
  ConsumerState<PtyTerminalView> createState() => _PtyTerminalViewState();
}

class _PtyTerminalViewState extends ConsumerState<PtyTerminalView> {
  final Terminal _terminal = Terminal(maxLines: 5000);
  StreamSubscription<String>? _shellSubscription;

  int _lastOutputIndex = 0;
  bool _startingShell = false;
  Timer? _resizeDebounce;
  int _lastCols = 0;
  int _lastRows = 0;

  static const double _hPadding = 20; // TerminalView padding is all(10)
  static const double _vPadding = 20;
  static const double _charWidth = 7.5; // JetBrainsMono @ 12.5
  static const double _lineHeight = 16.25; // 12.5 * 1.3

  @override
  void initState() {
    super.initState();
    _terminal.onOutput = (data) {
      if (widget.client.isShellActive) {
        widget.client.shellInput(data);
      }
    };
    _attachClient(widget.client);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startShell());
  }

  @override
  void didUpdateWidget(covariant PtyTerminalView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      _detachClient(oldWidget.client);
      _attachClient(widget.client);
      WidgetsBinding.instance.addPostFrameCallback((_) => _startShell());
    }
  }

  @override
  void dispose() {
    _detachClient(widget.client);
    widget.client.closeShell();
    _resizeDebounce?.cancel();
    ref.read(terminalFocusProvider.notifier).state = false;
    super.dispose();
  }

  void _attachClient(TerminalProxyClient client) {
    client.addListener(_onClientUpdate);
    _shellSubscription = client.shellOutput.listen(_terminal.write);
    _lastOutputIndex = client.outputs.length;
    _drainSystemOutputs();
  }

  void _detachClient(TerminalProxyClient client) {
    client.removeListener(_onClientUpdate);
    _shellSubscription?.cancel();
    _shellSubscription = null;
  }

  void _onClientUpdate() {
    _drainSystemOutputs();
    if (widget.client.isShellActive) {
      _startingShell = false;
    }
    if (mounted) setState(() {});
  }

  void _drainSystemOutputs() {
    final outputs = widget.client.outputs;
    if (_lastOutputIndex >= outputs.length) return;
    for (final output in outputs.sublist(_lastOutputIndex)) {
      final text = output.data ?? output.message;
      if (text == null || text.isEmpty) continue;
      if (output.type == 'shell_output') continue;
      _terminal.write('\r\n[$output.type] $text\r\n');
    }
    _lastOutputIndex = outputs.length;
    _startingShell = false;
  }

  Future<void> _startShell() async {
    if (_startingShell || widget.client.isShellActive) return;
    setState(() => _startingShell = true);
    try {
      if (!widget.client.isConnected || !widget.client.isAuthenticated) {
        await widget.client.connect();
      }
      final cols = _lastCols > 0 ? _lastCols : widget.cols;
      final rows = _lastRows > 0 ? _lastRows : widget.rows;
      widget.client.startShell(cols, rows);
    } catch (e) {
      _terminal.write('\r\n[error] failed to start interactive shell: $e\r\n');
      if (mounted) setState(() => _startingShell = false);
    }
  }

  void _handleViewportSize(Size size) {
    final cols = ((size.width - _hPadding) / _charWidth).floor().clamp(40, 500);
    final rows = ((size.height - _vPadding) / _lineHeight).floor().clamp(10, 200);
    if (cols == _lastCols && rows == _lastRows) return;
    _lastCols = cols;
    _lastRows = rows;

    _resizeDebounce?.cancel();
    _resizeDebounce = Timer(const Duration(milliseconds: 80), () {
      if (!mounted || !widget.client.isShellActive) return;
      widget.client.shellResize(cols, rows);
    });
  }

  Future<void> _pasteClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text;
    if (text == null || text.isEmpty || !widget.client.isShellActive) return;
    widget.client.shellInput(text);
  }

  Future<void> _resetShell() async {
    widget.client.closeShell();
    _terminal.write('\x1b[2J\x1b[H');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    await _startShell();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = ShellTokens.of(context);
    final isReady = widget.client.isShellActive;
    final statusText = 'interactive shell';
    final statusColor = isReady
        ? t.accentPrimary
        : (_startingShell ? t.accentSecondary : t.fgMuted);

    return Column(
      children: [
        if (widget.showHeader)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
            ),
            child: Row(
              children: [
                Text(
                  statusText,
                  style: theme.textTheme.labelSmall?.copyWith(color: statusColor),
                ),
                const SizedBox(width: 10),
                Text(
                  _startingShell ? 'starting...' : 'cwd shown in prompt',
                  style: theme.textTheme.labelSmall?.copyWith(color: t.fgTertiary),
                ),
                const Spacer(),
                if (isReady) ...[
                  _HeaderAction(
                    label: 'paste',
                    onTap: () {
                      _pasteClipboard();
                    },
                    color: t.fgMuted,
                    theme: theme,
                  ),
                  const SizedBox(width: 8),
                  _HeaderAction(
                    label: 'reset',
                    onTap: () {
                      _resetShell();
                    },
                    color: t.statusWarning,
                    theme: theme,
                  ),
                  const SizedBox(width: 10),
                ],
                if (!isReady)
                  GestureDetector(
                    onTap: _startingShell ? null : _startShell,
                    child: Text(
                      'start shell',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: _startingShell ? t.fgDisabled : t.accentPrimary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _handleViewportSize(constraints.biggest);
              return Focus(
                onFocusChange: (focused) {
                  ref.read(terminalFocusProvider.notifier).state = focused;
                },
                child: Container(
                  width: double.infinity,
                  color: t.surfaceBase,
                  child: TerminalView(
                    _terminal,
                    autofocus: true,
                    padding: const EdgeInsets.all(10),
                    backgroundOpacity: 1,
                    cursorType: TerminalCursorType.block,
                    textStyle: const TerminalStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 12.5,
                      height: 1.3,
                    ),
                  ),
                ),
                );
              },
          ),
        ),
      ],
    );
  }
}

class _HeaderAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color color;
  final ThemeData theme;

  const _HeaderAction({
    required this.label,
    required this.onTap,
    required this.color,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(color: color),
        ),
      ),
    );
  }
}
