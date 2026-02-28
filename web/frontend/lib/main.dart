import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme.dart';
import 'features/shell/shell_page.dart';

final themeModeProvider = StateProvider<ThemeMode>((ref) => loadThemeMode());

void main() {
  runApp(const ProviderScope(child: TrinityApp()));
}

class TrinityApp extends ConsumerWidget {
  const TrinityApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'Trinity AGI',
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: buildTheme(lightTokens, Brightness.light),
      darkTheme: buildTheme(darkTokens, Brightness.dark),
      home: const ShellPage(),
    );
  }
}
