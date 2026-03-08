import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import '../../core/terminal_client.dart';
import '../../core/theme.dart';
import 'xterm_interop.dart';

/// Embeds an xterm.js terminal connected to an interactive PTY shell session
/// via the TerminalProxyClient.
class InteractiveShellView extends StatefulWidget {
  final TerminalProxyClient client;

  const InteractiveShellView({super.key, required this.client});

  @override
  State<InteractiveShellView> createState() => _InteractiveShellViewState();
}

class _InteractiveShellViewState extends State<InteractiveShellView> {
  static int _viewIdCounter = 0;
  late final String _viewType;
  late final html.DivElement _hostDiv;

  XtermJs? _xterm;
  StreamSubscription<String>? _outputSub;
  bool _shellStarted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _viewType = 'xterm-shell-${_viewIdCounter++}';

    _hostDiv = html.DivElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.backgroundColor = '#0A0A0A';

    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _hostDiv,
    );

    widget.client.addListener(_onClientChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initXterm();
    });
  }

  void _initXterm() {
    _xterm = XtermJs(
      fontFamily: 'JetBrains Mono, IBM Plex Mono, monospace',
      fontSize: 13,
    );
    _xterm!.open(_hostDiv);

    _xterm!.onData((data) {
      widget.client.shellInput(data);
    });

    _outputSub = widget.client.shellOutput.listen((data) {
      _xterm?.write(data);
    });

    _startShell();
  }

  void _startShell() {
    if (!widget.client.isAuthenticated) {
      setState(() => _error = 'Not connected to terminal proxy');
      return;
    }
    final cols = _xterm?.cols ?? 80;
    final rows = _xterm?.rows ?? 24;
    widget.client.startShell(cols, rows);
  }

  void _onClientChanged() {
    if (!mounted) return;
    final active = widget.client.isShellActive;
    if (active != _shellStarted) {
      setState(() {
        _shellStarted = active;
        if (active) _error = null;
      });
      if (active) {
        _xterm?.focus();
      }
    }
  }

  @override
  void dispose() {
    widget.client.removeListener(_onClientChanged);
    _outputSub?.cancel();
    if (widget.client.isShellActive) {
      widget.client.closeShell();
    }
    _xterm?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: t.surfaceCard,
            child: Text(
              _error!,
              style: TextStyle(color: t.statusError, fontSize: 11),
            ),
          ),
        Expanded(
          child: HtmlElementView(viewType: _viewType),
        ),
      ],
    );
  }
}
