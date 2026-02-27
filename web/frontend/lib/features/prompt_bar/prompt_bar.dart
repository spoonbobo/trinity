import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../shell/shell_page.dart';
import 'voice_input.dart';

class PromptBar extends ConsumerStatefulWidget {
  final bool enabled;
  final VoidCallback onCanvasToggle;
  final VoidCallback onGovernanceToggle;
  final bool showCanvas;
  final bool showGovernance;

  const PromptBar({
    super.key,
    required this.enabled,
    required this.onCanvasToggle,
    required this.onGovernanceToggle,
    required this.showCanvas,
    required this.showGovernance,
  });

  @override
  ConsumerState<PromptBar> createState() => _PromptBarState();
}

class _PromptBarState extends ConsumerState<PromptBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _voiceController = VoiceInputController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _voiceController.initialize();
    _voiceController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _voiceController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.enabled || _sending) return;

    setState(() => _sending = true);
    _controller.clear();

    try {
      final client = ref.read(gatewayClientProvider);
      await client.sendChatMessage(text);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    _focusNode.requestFocus();
  }

  void _toggleVoice() {
    if (_voiceController.isListening) {
      _voiceController.stopListening();
    } else {
      _voiceController.startListening(
        onResult: (transcript) {
          _controller.text = transcript;
          _send();
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isListening = _voiceController.isListening;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F0F),
        border: Border(top: BorderSide(color: Color(0xFF2A2A2A))),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isListening && _voiceController.transcript.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _voiceController.transcript,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF6EE7B7),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            Row(
              children: [
                // Panel toggles
                _PanelToggle(
                  icon: Icons.grid_view_rounded,
                  active: widget.showCanvas,
                  onTap: widget.onCanvasToggle,
                  tooltip: 'Canvas',
                ),
                const SizedBox(width: 4),
                _PanelToggle(
                  icon: Icons.shield_outlined,
                  active: widget.showGovernance,
                  onTap: widget.onGovernanceToggle,
                  tooltip: 'Governance',
                ),
                const SizedBox(width: 8),
                // Text input
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    enabled: widget.enabled && !_sending,
                    maxLines: 3,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    style: theme.textTheme.bodyLarge,
                    decoration: InputDecoration(
                      hintText: widget.enabled
                          ? 'Ask anything...'
                          : 'Connecting to gateway...',
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                // Voice button
                if (_voiceController.isAvailable)
                  _ActionButton(
                    icon: isListening ? Icons.stop_rounded : Icons.mic_rounded,
                    color: isListening
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF6EE7B7),
                    onTap: _toggleVoice,
                    tooltip: isListening ? 'Stop listening' : 'Voice input',
                  ),
                const SizedBox(width: 4),
                // Send button
                _ActionButton(
                  icon: _sending
                      ? Icons.hourglass_top_rounded
                      : Icons.arrow_upward_rounded,
                  color: const Color(0xFF6EE7B7),
                  onTap: _sending ? null : _send,
                  tooltip: 'Send',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelToggle extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final String tooltip;

  const _PanelToggle({
    required this.icon,
    required this.active,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: active ? const Color(0xFF1A2A1A) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? const Color(0xFF6EE7B7) : const Color(0xFF2A2A2A),
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: active ? const Color(0xFF6EE7B7) : const Color(0xFF6B6B6B),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final String tooltip;

  const _ActionButton({
    required this.icon,
    required this.color,
    this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}
