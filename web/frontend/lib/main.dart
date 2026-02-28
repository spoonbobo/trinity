import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/shell/shell_page.dart';

void main() {
  runApp(const ProviderScope(child: TrinityApp()));
}

class TrinityApp extends StatelessWidget {
  const TrinityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trinity AGI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        colorScheme: ColorScheme.dark(
          surface: const Color(0xFF0A0A0A),
          primary: const Color(0xFF6EE7B7),
          secondary: const Color(0xFF3B82F6),
          error: const Color(0xFFEF4444),
          onSurface: const Color(0xFFE5E5E5),
          onPrimary: const Color(0xFF0A0A0A),
          outline: const Color(0xFF2A2A2A),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF141414),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF2A2A2A)),
          ),
          elevation: 0,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(
            fontFamily: 'monofur',
            color: Color(0xFFE5E5E5),
            fontSize: 14,
          ),
          bodyMedium: TextStyle(
            fontFamily: 'monofur',
            color: Color(0xFFB0B0B0),
            fontSize: 13,
          ),
          titleLarge: TextStyle(
            fontFamily: 'monofur',
            color: Color(0xFFE5E5E5),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
          labelSmall: TextStyle(
            fontFamily: 'monofur',
            color: Color(0xFF6B6B6B),
            fontSize: 11,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF141414),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF6EE7B7)),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          hintStyle: const TextStyle(
            fontFamily: 'monofur',
            color: Color(0xFF4A4A4A),
            fontSize: 13,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF6EE7B7)),
      ),
      home: const ShellPage(),
    );
  }
}
