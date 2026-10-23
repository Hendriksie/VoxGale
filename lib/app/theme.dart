import 'package:flutter/material.dart';

/// Mistral orange — the brand accent, used sparingly for the recording state,
/// CTAs, and other accents in both themes.
const Color mistralOrange = Color(0xFFFF7000);

/// Light theme, seeded with Mistral orange (Material 3).
ThemeData buildLightTheme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: mistralOrange,
        brightness: Brightness.light,
      ),
      useMaterial3: true,
    );

/// Dark theme, seeded with Mistral orange (Material 3).
ThemeData buildDarkTheme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: mistralOrange,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    );
