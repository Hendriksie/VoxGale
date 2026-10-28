import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxgale/app/live_session_screen.dart';
import 'package:voxgale/app/theme.dart';

import 'app/fakes.dart';

void main() {
  testWidgets('app shell renders with Mistral orange themes in both modes',
      (tester) async {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      // A saved key keeps the home screen in its idle state (with no key,
      // the missing-key precondition state shows — empty-error-states spec).
      await tester.pumpWidget(appWithStore(
        FakeApiKeyStore()..key = 'test-key',
        themeMode: mode,
      ));
      await tester.pumpAndSettle();

      // Read the theme from below the MaterialApp (the MaterialApp element
      // itself sits above the Theme it provides).
      final context = tester.element(find.byType(LiveSessionScreen));
      final theme = Theme.of(context);
      final expectedScheme = ColorScheme.fromSeed(
        seedColor: mistralOrange,
        brightness:
            mode == ThemeMode.light ? Brightness.light : Brightness.dark,
      );

      expect(theme.brightness, expectedScheme.brightness);
      expect(theme.colorScheme.primary, expectedScheme.primary);
      // Home is the live session screen (design P1-D6).
      expect(find.text('VoxGale'), findsOneWidget);
      expect(find.text('Start a session to see the live transcript.'),
          findsOneWidget);
      expect(find.text('Start'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });
}
