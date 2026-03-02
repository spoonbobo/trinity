import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import '../../core/theme.dart';
import '../../core/dialog_service.dart';
import 'canvas_mode_provider.dart';
import 'a2ui_renderer.dart';
import 'drawio_renderer.dart';

/// Unified canvas panel: A2UI | DrawIO.
/// Mode toggle and draw.io toolbar fixed at bottom-right.
class CanvasPanel extends ConsumerStatefulWidget {
  const CanvasPanel({super.key});

  @override
  ConsumerState<CanvasPanel> createState() => _CanvasPanelState();
}

class _CanvasPanelState extends ConsumerState<CanvasPanel> {
  final GlobalKey<DrawIORendererState> _drawioKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(canvasModeProvider);
    final modeNotifier = ref.read(canvasModeProvider.notifier);
    final t = ShellTokens.of(context);

    return Stack(
      children: [
        // Renderer area
        Positioned.fill(
          child: switch (mode) {
            CanvasMode.a2ui => const A2UIRendererPanel(),
            CanvasMode.drawio => ValueListenableBuilder<bool>(
                valueListenable: DialogService.instance.dialogIsOpenNotifier,
                builder: (context, dialogIsOpen, child) => DrawIORenderer(
                  key: _drawioKey,
                  dialogIsOpen: dialogIsOpen,
                ),
              ),
          },
        ),

        // Mode toggle – bottom-right
        Positioned(
          bottom: 4,
          right: 4,
          child: PointerInterceptor(
            child: _ModeToggle(
              currentMode: mode,
              onModeChanged: (newMode) {
                modeNotifier.setMode(newMode);
              },
              tokens: t,
            ),
          ),
        ),

        // Draw.io toolbar – bottom-right above mode toggle
        if (mode == CanvasMode.drawio)
          Positioned(
            bottom: 36,
            right: 4,
            child: PointerInterceptor(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SmallButton(
                    icon: Icons.content_copy,
                    tooltip: 'copy image',
                    onTap: () => _drawioKey.currentState?.copyPng(),
                    tokens: t,
                  ),
                  const SizedBox(width: 2),
                  _SmallButton(
                    icon: Icons.download,
                    tooltip: 'export PNG',
                    onTap: () => _drawioKey.currentState?.exportPng(),
                    tokens: t,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Mode toggle
// ---------------------------------------------------------------------------

class _ModeToggle extends StatelessWidget {
  final CanvasMode currentMode;
  final ValueChanged<CanvasMode> onModeChanged;
  final ShellTokens tokens;

  const _ModeToggle({
    required this.currentMode,
    required this.onModeChanged,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: kShellBorderRadiusSm,
        color: tokens.surfaceBase.withOpacity(0.95),
        border: Border.all(color: tokens.border, width: 0.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeButton(
            label: 'a2ui',
            isSelected: currentMode == CanvasMode.a2ui,
            onTap: () => onModeChanged(CanvasMode.a2ui),
            tokens: tokens,
          ),
          _divider(),
          _ModeButton(
            label: 'drawio',
            isSelected: currentMode == CanvasMode.drawio,
            onTap: () => onModeChanged(CanvasMode.drawio),
            tokens: tokens,
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 14,
        color: tokens.border,
        margin: const EdgeInsets.symmetric(horizontal: 2),
      );
}

class _ModeButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final ShellTokens tokens;

  const _ModeButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isSelected ? null : onTap,
      child: MouseRegion(
        cursor: isSelected ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: kShellBorderRadiusSm,
            color: isSelected
                ? tokens.accentPrimary.withOpacity(0.15)
                : Colors.transparent,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected ? tokens.accentPrimary : tokens.fgMuted,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final ShellTokens tokens;

  const _SmallButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              borderRadius: kShellBorderRadiusSm,
              color: tokens.surfaceBase.withOpacity(0.8),
              border: Border.all(color: tokens.border, width: 0.5),
            ),
            child: Icon(icon, size: 12, color: tokens.fgMuted),
          ),
        ),
      ),
    );
  }
}
