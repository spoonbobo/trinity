import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import '../terminal/interactive_shell_view.dart';

/// Admin tab that provides a full interactive PTY shell (superadmin only).
class AdminShellTab extends ConsumerStatefulWidget {
  const AdminShellTab({super.key});

  @override
  ConsumerState<AdminShellTab> createState() => _AdminShellTabState();
}

class _AdminShellTabState extends ConsumerState<AdminShellTab> {
  bool _started = false;

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    final client = ref.watch(terminalClientProvider);

    if (!client.isConnected) {
      return Center(
        child: Text(
          'terminal proxy not connected',
          style: theme.textTheme.bodySmall?.copyWith(color: t.fgPlaceholder),
        ),
      );
    }

    if (!_started) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'interactive shell',
              style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              'opens a PTY session into the openclaw pod',
              style: theme.textTheme.bodySmall?.copyWith(
                color: t.fgMuted,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => setState(() => _started = true),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: t.accentPrimary, width: 0.5),
                  borderRadius: kShellBorderRadius,
                ),
                child: Text(
                  'start shell',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: t.accentPrimary),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return InteractiveShellView(client: client);
  }
}
