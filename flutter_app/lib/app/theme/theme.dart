import 'package:flutter/material.dart';

abstract final class Tokens {
  static const authIvory = Color(0xFFF6F5EE);
  static const authForest = Color(0xFF0C2926);
  static const authMuted = Color(0xFF536862);
  static const authTeal = Color(0xFF0F786B);
  static const authSoft = Color(0xFFDFF1EA);
  static const authGold = Color(0xFFF8DB9B);
  static const authBorder = Color(0xFFCDD8D1);
  static const forest = Color(0xFF244D3E);
  static const lime = Color(0xFFD4E8AD);
  static const cream = Color(0xFFF7F7F0);
  static const ink = Color(0xFF202E27);
  static const muted = Color(0xFF626C62);
  static const gold = Color(0xFFB78B4F);
  static const radius = 24.0;
  static const gap = 16.0;
  static const target = 48.0;
  static const motion = Duration(milliseconds: 220);

  static ThemeData theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: forest,
          brightness: brightness,
        ).copyWith(
          primary: dark ? lime : forest,
          onPrimary: dark ? ink : Colors.white,
          secondaryContainer: dark
              ? const Color(0xFF334938)
              : const Color(0xFFEAF0DF),
          surface: dark ? const Color(0xFF18231E) : const Color(0xFFFFFEFA),
          onSurface: dark ? const Color(0xFFE8EEE2) : ink,
          onSurfaceVariant: dark ? const Color(0xFFB9C4B7) : muted,
          outlineVariant: dark
              ? const Color(0xFF36443A)
              : const Color(0xFFE1E5D9),
        );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'NotoSansKhmer',
      brightness: brightness,
    );
    return base.copyWith(
      scaffoldBackgroundColor: dark ? const Color(0xFF111B16) : cream,
      textTheme: base.textTheme.copyWith(
        headlineLarge: base.textTheme.headlineLarge!.copyWith(
          fontSize: 34,
          fontWeight: FontWeight.w600,
          height: 1.4,
          letterSpacing: -1.3,
        ),
        headlineMedium: base.textTheme.headlineMedium!.copyWith(
          fontSize: 26,
          fontWeight: FontWeight.w600,
          height: 1.45,
          letterSpacing: -.6,
        ),
        titleLarge: base.textTheme.titleLarge!.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          height: 1.45,
        ),
        titleMedium: base.textTheme.titleMedium!.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          height: 1.6,
        ),
        bodyMedium: base.textTheme.bodyMedium!.copyWith(height: 1.65),
        bodySmall: base.textTheme.bodySmall!.copyWith(height: 1.6),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? const Color(0xFF111B16) : cream,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 54),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.secondaryContainer,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontFamily: 'NotoSansKhmer',
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        side: BorderSide(color: scheme.outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
    );
  }
}
