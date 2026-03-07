import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import 'browser_provider.dart';

/// Renders the OpenClaw-managed browser on the canvas panel.
///
/// Architecture:
/// - Polls the gateway's browser control HTTP API for screenshots
/// - Renders the screenshot as an image with interactive overlays
/// - Translates user clicks/types to browser actions via the API
/// - Supports tab management, navigation, and snapshot inspection
class BrowserRenderer extends ConsumerStatefulWidget {
  const BrowserRenderer({super.key});

  @override
  ConsumerState<BrowserRenderer> createState() => BrowserRendererState();
}

class BrowserRendererState extends ConsumerState<BrowserRenderer> {
  final _urlController = TextEditingController();
  final _urlFocusNode = FocusNode();
  bool _urlEditing = false;
  bool _showSnapshot = false;

  @override
  void initState() {
    super.initState();
    // Trigger initial status check + start polling when widget is first shown
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier = ref.read(browserProvider.notifier);
      notifier.refreshStatus();
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _urlFocusNode.dispose();
    super.dispose();
  }

  void _onUrlSubmitted(String value) {
    if (value.trim().isEmpty) return;
    ref.read(browserProvider.notifier).navigate(value.trim());
    _urlFocusNode.unfocus();
    setState(() => _urlEditing = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(browserProvider);
    final t = ShellTokens.of(context);

    return Container(
      color: t.surfaceBase,
      child: Column(
        children: [
          // ── Chrome toolbar (URL bar + nav) ─────────────────────
          _BrowserToolbar(
            url: state.currentUrl ?? '',
            isLoading: state.isLoading,
            urlController: _urlController,
            urlFocusNode: _urlFocusNode,
            isEditing: _urlEditing,
            onEditStart: () => setState(() {
              _urlEditing = true;
              _urlController.text = state.currentUrl ?? '';
              _urlController.selection = TextSelection(
                baseOffset: 0,
                extentOffset: _urlController.text.length,
              );
            }),
            onEditEnd: () => setState(() => _urlEditing = false),
            onUrlSubmitted: _onUrlSubmitted,
            onBack: () => ref.read(browserProvider.notifier).goBack(),
            onForward: () => ref.read(browserProvider.notifier).goForward(),
            onRefresh: () => ref.read(browserProvider.notifier).manualRefresh(),
            tokens: t,
          ),

          // ── Tab strip ──────────────────────────────────────────
          if (state.runState == BrowserRunState.running && state.tabs.isNotEmpty)
            _TabStrip(
              tabs: state.tabs,
              activeTabId: state.activeTabId,
              onTabTap: (id) => ref.read(browserProvider.notifier).focusTab(id),
              onTabClose: (id) => ref.read(browserProvider.notifier).closeTab(id),
              onNewTab: () => ref.read(browserProvider.notifier).openTab(),
              tokens: t,
            ),

          // ── Main viewport ──────────────────────────────────────
          Expanded(
            child: _buildViewport(state, t),
          ),

          // ── Status bar ─────────────────────────────────────────
          _StatusBar(
            state: state,
            showSnapshot: _showSnapshot,
            onToggleSnapshot: () => setState(() {
              _showSnapshot = !_showSnapshot;
              if (_showSnapshot) {
                ref.read(browserProvider.notifier).refreshSnapshot();
              }
            }),
            onToggleAutoRefresh: () =>
                ref.read(browserProvider.notifier).toggleAutoRefresh(),
            tokens: t,
          ),
        ],
      ),
    );
  }

  Widget _buildViewport(BrowserState state, ShellTokens t) {
    // ── Not running: show start button ───────────────────────
    if (state.runState == BrowserRunState.unknown ||
        state.runState == BrowserRunState.stopped) {
      return _StartScreen(
        onStart: () => ref.read(browserProvider.notifier).startBrowser(),
        error: state.error,
        tokens: t,
      );
    }

    // ── Starting: show spinner ───────────────────────────────
    if (state.runState == BrowserRunState.starting) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: t.accentPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text('starting browser...',
                style: TextStyle(fontSize: 11, color: t.fgMuted)),
          ],
        ),
      );
    }

    // ── Error state ──────────────────────────────────────────
    if (state.runState == BrowserRunState.error) {
      return _ErrorScreen(
        error: state.error ?? 'Unknown error',
        onRetry: () => ref.read(browserProvider.notifier).refreshStatus(),
        tokens: t,
      );
    }

    // ── Running: show screenshot (+ optional snapshot overlay) ─
    if (state.screenshotBytes == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.web, size: 24, color: t.fgMuted),
            const SizedBox(height: 8),
            Text('waiting for screenshot...',
                style: TextStyle(fontSize: 11, color: t.fgMuted)),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => ref.read(browserProvider.notifier).manualRefresh(),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: kShellBorderRadiusSm,
                    border: Border.all(color: t.border, width: 0.5),
                  ),
                  child: Text('refresh',
                      style: TextStyle(fontSize: 10, color: t.accentPrimary)),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        // Screenshot image
        Positioned.fill(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 3.0,
            child: Image.memory(
              state.screenshotBytes!,
              fit: BoxFit.contain,
              gaplessPlayback: true, // Prevent flicker between frames
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),

        // Loading overlay during refresh
        if (state.isLoading)
          Positioned(
            top: 4, right: 4,
            child: SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: t.accentPrimary.withOpacity(0.5),
              ),
            ),
          ),

        // Snapshot text overlay (toggled via status bar)
        if (_showSnapshot && state.snapshotText != null && state.snapshotText!.isNotEmpty)
          Positioned.fill(
            child: Container(
              color: t.surfaceBase.withOpacity(0.85),
              padding: const EdgeInsets.all(8),
              child: SingleChildScrollView(
                child: SelectionArea(
                  child: Text(
                    state.snapshotText!,
                    style: TextStyle(
                      fontSize: 10,
                      color: t.fgSecondary,
                      fontFamily: 'monospace',
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Browser toolbar (URL bar + navigation buttons)
// ---------------------------------------------------------------------------

class _BrowserToolbar extends StatelessWidget {
  final String url;
  final bool isLoading;
  final TextEditingController urlController;
  final FocusNode urlFocusNode;
  final bool isEditing;
  final VoidCallback onEditStart;
  final VoidCallback onEditEnd;
  final ValueChanged<String> onUrlSubmitted;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onRefresh;
  final ShellTokens tokens;

  const _BrowserToolbar({
    required this.url,
    required this.isLoading,
    required this.urlController,
    required this.urlFocusNode,
    required this.isEditing,
    required this.onEditStart,
    required this.onEditEnd,
    required this.onUrlSubmitted,
    required this.onBack,
    required this.onForward,
    required this.onRefresh,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        border: Border(bottom: BorderSide(color: tokens.border, width: 0.5)),
      ),
      child: Row(
        children: [
          // Back
          _NavButton(
            icon: Icons.arrow_back,
            onTap: onBack,
            tooltip: 'Back',
            tokens: tokens,
          ),
          const SizedBox(width: 2),
          // Forward
          _NavButton(
            icon: Icons.arrow_forward,
            onTap: onForward,
            tooltip: 'Forward',
            tokens: tokens,
          ),
          const SizedBox(width: 2),
          // Refresh / Stop
          _NavButton(
            icon: isLoading ? Icons.close : Icons.refresh,
            onTap: onRefresh,
            tooltip: isLoading ? 'Stop' : 'Refresh',
            tokens: tokens,
          ),
          const SizedBox(width: 6),
          // URL bar
          Expanded(
            child: GestureDetector(
              onTap: isEditing ? null : onEditStart,
              child: Container(
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  borderRadius: kShellBorderRadiusSm,
                  color: tokens.surfaceBase,
                  border: Border.all(
                    color: isEditing
                        ? tokens.accentPrimary.withOpacity(0.5)
                        : tokens.border,
                    width: 0.5,
                  ),
                ),
                alignment: Alignment.centerLeft,
                child: isEditing
                    ? TextField(
                        controller: urlController,
                        focusNode: urlFocusNode,
                        autofocus: true,
                        style: TextStyle(
                          fontSize: 11,
                          color: tokens.fgPrimary,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onSubmitted: onUrlSubmitted,
                        onEditingComplete: onEditEnd,
                      )
                    : Row(
                        children: [
                          if (url.startsWith('https://'))
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(Icons.lock,
                                  size: 10, color: tokens.accentPrimary),
                            ),
                          Expanded(
                            child: Text(
                              _displayUrl(url),
                              style: TextStyle(
                                fontSize: 11,
                                color: tokens.fgSecondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Strip protocol for display.
  static String _displayUrl(String url) {
    if (url.isEmpty) return '';
    return url
        .replaceFirst('https://', '')
        .replaceFirst('http://', '');
  }
}

class _NavButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final ShellTokens tokens;

  const _NavButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    required this.tokens,
  });

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: GestureDetector(
        onTap: widget.onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              borderRadius: kShellBorderRadiusSm,
              color: _hovering
                  ? widget.tokens.surfaceElevated.withOpacity(0.5)
                  : Colors.transparent,
            ),
            child: Icon(
              widget.icon,
              size: 14,
              color: _hovering
                  ? widget.tokens.fgPrimary
                  : widget.tokens.fgMuted,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab strip
// ---------------------------------------------------------------------------

class _TabStrip extends StatelessWidget {
  final List<BrowserTab> tabs;
  final String? activeTabId;
  final ValueChanged<String> onTabTap;
  final ValueChanged<String> onTabClose;
  final VoidCallback onNewTab;
  final ShellTokens tokens;

  const _TabStrip({
    required this.tabs,
    required this.activeTabId,
    required this.onTabTap,
    required this.onTabClose,
    required this.onNewTab,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        border: Border(bottom: BorderSide(color: tokens.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              children: [
                for (final tab in tabs)
                  _TabChip(
                    tab: tab,
                    isActive: tab.targetId == activeTabId,
                    onTap: () => onTabTap(tab.targetId),
                    onClose: () => onTabClose(tab.targetId),
                    tokens: tokens,
                  ),
              ],
            ),
          ),
          // New tab button
          GestureDetector(
            onTap: onNewTab,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                width: 24, height: 24,
                margin: const EdgeInsets.only(right: 4),
                child: Icon(Icons.add, size: 14, color: tokens.fgMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatefulWidget {
  final BrowserTab tab;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final ShellTokens tokens;

  const _TabChip({
    required this.tab,
    required this.isActive,
    required this.onTap,
    required this.onClose,
    required this.tokens,
  });

  @override
  State<_TabChip> createState() => _TabChipState();
}

class _TabChipState extends State<_TabChip> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 160, minWidth: 60),
          margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: kShellBorderRadiusSm,
            color: widget.isActive
                ? widget.tokens.surfaceBase
                : _hovering
                    ? widget.tokens.surfaceElevated.withOpacity(0.3)
                    : Colors.transparent,
            border: widget.isActive
                ? Border.all(color: widget.tokens.border, width: 0.5)
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  widget.tab.title.isEmpty ? 'New Tab' : widget.tab.title,
                  style: TextStyle(
                    fontSize: 10,
                    color: widget.isActive
                        ? widget.tokens.fgPrimary
                        : widget.tokens.fgMuted,
                    overflow: TextOverflow.ellipsis,
                  ),
                  maxLines: 1,
                ),
              ),
              if (_hovering || widget.isActive) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: widget.onClose,
                  child: Icon(Icons.close, size: 10, color: widget.tokens.fgMuted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Start screen (browser not running)
// ---------------------------------------------------------------------------

class _StartScreen extends StatelessWidget {
  final VoidCallback onStart;
  final String? error;
  final ShellTokens tokens;

  const _StartScreen({
    required this.onStart,
    this.error,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              borderRadius: kShellBorderRadius,
              border: Border.all(color: tokens.border, width: 0.5),
            ),
            child: Icon(Icons.language, size: 24, color: tokens.fgMuted),
          ),
          const SizedBox(height: 16),
          Text('openclaw managed browser',
              style: TextStyle(fontSize: 12, color: tokens.fgSecondary)),
          const SizedBox(height: 4),
          Text('isolated chromium instance for agent + human collaboration',
              style: TextStyle(fontSize: 10, color: tokens.fgMuted)),
          if (error != null) ...[
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxWidth: 400),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                borderRadius: kShellBorderRadiusSm,
                color: tokens.statusError.withOpacity(0.1),
                border: Border.all(color: tokens.statusError.withOpacity(0.3), width: 0.5),
              ),
              child: Text(
                error!,
                style: TextStyle(fontSize: 9, color: tokens.statusError),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onStart,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: kShellBorderRadiusSm,
                  color: tokens.accentPrimary.withOpacity(0.15),
                  border: Border.all(color: tokens.accentPrimary.withOpacity(0.3), width: 0.5),
                ),
                child: Text('start browser',
                    style: TextStyle(
                      fontSize: 11,
                      color: tokens.accentPrimary,
                      fontWeight: FontWeight.w600,
                    )),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error screen
// ---------------------------------------------------------------------------

class _ErrorScreen extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  final ShellTokens tokens;

  const _ErrorScreen({
    required this.error,
    required this.onRetry,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 24, color: tokens.statusError),
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: kShellBorderRadiusSm,
              color: tokens.statusError.withOpacity(0.1),
              border: Border.all(color: tokens.statusError.withOpacity(0.3), width: 0.5),
            ),
            child: Text(
              error,
              style: TextStyle(fontSize: 10, color: tokens.fgSecondary),
              textAlign: TextAlign.center,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onRetry,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: kShellBorderRadiusSm,
                  border: Border.all(color: tokens.border, width: 0.5),
                ),
                child: Text('retry',
                    style: TextStyle(fontSize: 10, color: tokens.accentPrimary)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status bar
// ---------------------------------------------------------------------------

class _StatusBar extends StatelessWidget {
  final BrowserState state;
  final bool showSnapshot;
  final VoidCallback onToggleSnapshot;
  final VoidCallback onToggleAutoRefresh;
  final ShellTokens tokens;

  const _StatusBar({
    required this.state,
    required this.showSnapshot,
    required this.onToggleSnapshot,
    required this.onToggleAutoRefresh,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (state.runState) {
      BrowserRunState.running => tokens.accentPrimary,
      BrowserRunState.starting => tokens.statusWarning,
      BrowserRunState.error => tokens.statusError,
      _ => tokens.fgDisabled,
    };
    final statusLabel = switch (state.runState) {
      BrowserRunState.running => 'running',
      BrowserRunState.starting => 'starting',
      BrowserRunState.stopped => 'stopped',
      BrowserRunState.error => 'error',
      BrowserRunState.unknown => 'checking...',
    };

    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        border: Border(top: BorderSide(color: tokens.border, width: 0.5)),
      ),
      child: Row(
        children: [
          // Status dot + label
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(statusLabel,
              style: TextStyle(fontSize: 9, color: tokens.fgMuted)),
          const SizedBox(width: 8),

          // Profile name
          Text('profile: ${state.profile}',
              style: TextStyle(fontSize: 9, color: tokens.fgMuted)),

          // Tab count
          if (state.tabs.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text('${state.tabs.length} tab${state.tabs.length == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 9, color: tokens.fgMuted)),
          ],

          const Spacer(),

          // Snapshot toggle
          if (state.runState == BrowserRunState.running)
            GestureDetector(
              onTap: onToggleSnapshot,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    showSnapshot ? 'hide snapshot' : 'snapshot',
                    style: TextStyle(
                      fontSize: 9,
                      color: showSnapshot
                          ? tokens.accentPrimary
                          : tokens.fgMuted,
                    ),
                  ),
                ),
              ),
            ),

          // Auto-refresh toggle
          if (state.runState == BrowserRunState.running)
            GestureDetector(
              onTap: onToggleAutoRefresh,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      state.autoRefresh ? Icons.sync : Icons.sync_disabled,
                      size: 10,
                      color: state.autoRefresh
                          ? tokens.accentPrimary
                          : tokens.fgMuted,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      state.autoRefresh ? 'live' : 'paused',
                      style: TextStyle(
                        fontSize: 9,
                        color: state.autoRefresh
                            ? tokens.accentPrimary
                            : tokens.fgMuted,
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
