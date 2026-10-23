import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxtral_live/app/home_screen.dart';
import 'package:voxtral_live/app/theme.dart';
import 'package:voxtral_live/main.dart';
import 'package:voxtral_live/mistral/mistral.dart';
import 'package:voxtral_live/spike/spike_providers.dart';

/// In-memory [ApiKeyStore] for widget tests.
class FakeApiKeyStore implements ApiKeyStore {
  String? key;

  @override
  Future<String?> readKey() async => key;

  @override
  Future<void> saveKey(String newKey) async => key = newKey;

  @override
  Future<void> deleteKey() async => key = null;
}

ProviderScope appWithStore(ApiKeyStore store, {ThemeMode? themeMode}) =>
    ProviderScope(
      overrides: [apiKeyStoreProvider.overrideWith((ref) => store)],
      child: VoxtralLiveApp(themeMode: themeMode),
    );

void main() {
  testWidgets('app shell renders with Mistral orange themes in both modes',
      (tester) async {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      await tester
          .pumpWidget(appWithStore(FakeApiKeyStore(), themeMode: mode));
      await tester.pumpAndSettle();

      // Read the theme from below the MaterialApp (the MaterialApp element
      // itself sits above the Theme it provides).
      final context = tester.element(find.byType(HomeScreen));
      final theme = Theme.of(context);
      final expectedScheme = ColorScheme.fromSeed(
        seedColor: mistralOrange,
        brightness:
            mode == ThemeMode.light ? Brightness.light : Brightness.dark,
      );

      expect(theme.brightness, expectedScheme.brightness);
      expect(theme.colorScheme.primary, expectedScheme.primary);
      expect(find.text('Voxtral Live'), findsOneWidget);
      expect(find.text('Spike A — live transcription'), findsOneWidget);
      expect(find.text('Spike B — background capture'), findsOneWidget);
      expect(find.text('Spike C — batch transcription'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('debug API key entry saves the key to secure storage',
      (tester) async {
    final store = FakeApiKeyStore();
    await tester.pumpWidget(appWithStore(store, themeMode: ThemeMode.light));
    await tester.pumpAndSettle();

    await tester.tap(find.text('API key (debug)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'sk-test-key-123');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(store.key, 'sk-test-key-123');
    expect(find.text('API key saved to secure storage'), findsOneWidget);
  });

  testWidgets('debug API key entry can clear the key', (tester) async {
    final store = FakeApiKeyStore()..key = 'sk-existing';
    await tester.pumpWidget(appWithStore(store, themeMode: ThemeMode.light));
    await tester.pumpAndSettle();

    await tester.tap(find.text('API key (debug)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(store.key, isNull);
    expect(find.text('API key cleared'), findsOneWidget);
  });
}
