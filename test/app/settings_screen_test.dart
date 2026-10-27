// Widget tests for the settings screen (task 3.2, design P2-D4, Phase 3
// group 2): the key status (saved/not saved — the value is never displayed),
// save-with-validation (invalid key → the shared auth error banner, not
// saved; valid key → saved; unreachable API → the shared no-network banner
// with a retry action), key removal, and the persisted preferences (default
// batch model, language hint). The validator, key store, and preferences
// repository are test doubles — never real services, never the live API.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:voxtral_live/app/error_states.dart';
import 'package:voxtral_live/app/settings_screen.dart';
import 'package:voxtral_live/mistral/mistral.dart';
import 'package:voxtral_live/session/session_providers.dart';
import 'package:voxtral_live/storage/storage.dart';

import 'fakes.dart';

class MockKeyValidationClient extends Mock implements KeyValidationClient {}

void main() {
  late FakeApiKeyStore apiKeyStore;
  late MockKeyValidationClient validator;
  late InMemoryPreferencesRepository preferences;

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiKeyStoreProvider.overrideWith((ref) => apiKeyStore),
          keyValidationClientProvider.overrideWith((ref) => validator),
          preferencesRepositoryProvider.overrideWith((ref) => preferences),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();
  }

  /// Waits until the controller's initial load has completed.
  Future<void> waitLoaded(WidgetTester tester) async {
    await tester.pumpAndSettle();
  }

  setUp(() {
    apiKeyStore = FakeApiKeyStore();
    validator = MockKeyValidationClient();
    preferences = InMemoryPreferencesRepository();
    when(() => validator.validate(any())).thenAnswer((_) async {});
  });

  group('API key section (settings spec)', () {
    testWidgets('shows a missing-key state with the entry', (tester) async {
      await pumpSettings(tester);
      await waitLoaded(tester);

      expect(find.text('Not saved'), findsOneWidget);
      expect(find.text('Saved'), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Save key'), findsOneWidget);
    });

    testWidgets('shows the saved status without displaying the key',
        (tester) async {
      apiKeyStore.key = 'sk-secret-value';
      await pumpSettings(tester);
      await waitLoaded(tester);

      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('sk-secret-value'), findsNothing);
    });

    testWidgets('a valid key is validated, saved, and the status flips',
        (tester) async {
      await pumpSettings(tester);
      await waitLoaded(tester);

      await tester.enterText(find.byType(TextField), 'sk-new-key');
      await tester.tap(find.text('Save key'));
      await tester.pumpAndSettle();

      verify(() => validator.validate('sk-new-key')).called(1);
      expect(apiKeyStore.key, 'sk-new-key');
      expect(find.text('Saved'), findsOneWidget);
      // The key value is never displayed — only the saved state.
      expect(find.text('sk-new-key'), findsNothing);
    });

    testWidgets('an invalid key shows the shared auth error banner and is '
        'not saved', (tester) async {
      when(() => validator.validate(any()))
          .thenThrow(MistralApiException('The API key was rejected.'));
      await pumpSettings(tester);
      await waitLoaded(tester);

      await tester.enterText(find.byType(TextField), 'sk-bad');
      await tester.tap(find.text('Save key'));
      await tester.pumpAndSettle();

      // The shared taxonomy: an invalid key is an auth failure, rendered
      // through the inline error banner.
      expect(find.byType(ErrorBanner), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.text('The API key was rejected.'), findsOneWidget);
      expect(apiKeyStore.key, isNull);
      expect(find.text('Not saved'), findsOneWidget);
    });

    testWidgets('a validation network failure is retryable', (tester) async {
      var calls = 0;
      when(() => validator.validate(any())).thenAnswer((_) async {
        calls++;
        if (calls == 1) {
          throw MistralApiException('Could not reach the Mistral API.');
        }
      });
      await pumpSettings(tester);
      await waitLoaded(tester);

      await tester.enterText(find.byType(TextField), 'sk-flaky');
      await tester.tap(find.text('Save key'));
      await tester.pumpAndSettle();
      // The shared taxonomy: an unreachable API is a no-network failure.
      expect(find.byType(ErrorBanner), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
      expect(find.text('Could not reach the Mistral API.'), findsOneWidget);
      expect(apiKeyStore.key, isNull);

      await tester.tap(find.text('Save key'));
      await tester.pumpAndSettle();

      expect(apiKeyStore.key, 'sk-flaky');
      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets('the no-network error banner offers a retry action that '
        're-validates the entered key', (tester) async {
      var calls = 0;
      when(() => validator.validate(any())).thenAnswer((_) async {
        calls++;
        if (calls == 1) {
          throw MistralApiException('Could not reach the Mistral API.');
        }
      });
      await pumpSettings(tester);
      await waitLoaded(tester);

      await tester.enterText(find.byType(TextField), 'sk-flaky');
      await tester.tap(find.text('Save key'));
      await tester.pumpAndSettle();
      expect(find.byType(ErrorBanner), findsOneWidget);

      // The banner's retry action re-validates the key still in the field.
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(calls, 2);
      expect(apiKeyStore.key, 'sk-flaky');
      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets('the validating state is shown while the request is in flight',
        (tester) async {
      final completer = Completer<void>();
      when(() => validator.validate(any())).thenAnswer((_) => completer.future);
      await pumpSettings(tester);
      await waitLoaded(tester);

      await tester.enterText(find.byType(TextField), 'sk-pending');
      await tester.tap(find.text('Save key'));
      await tester.pump();

      expect(find.text('Validating…'), findsOneWidget);

      completer.complete();
      await tester.pumpAndSettle();
      expect(apiKeyStore.key, 'sk-pending');
    });

    testWidgets('removing the key asks for confirmation and clears the store',
        (tester) async {
      apiKeyStore.key = 'sk-existing';
      await pumpSettings(tester);
      await waitLoaded(tester);

      await tester.tap(find.text('Remove key'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(apiKeyStore.key, isNull);
      expect(find.text('Not saved'), findsOneWidget);
    });
  });

  group('preferences section (settings spec)', () {
    testWidgets('the default batch model defaults to Mini and persists a '
        'change', (tester) async {
      await pumpSettings(tester);
      await waitLoaded(tester);

      // Mini is selected by default (the pinned fallback).
      final segmented =
          tester.widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>));
      expect(
        segmented.selected,
        {MistralConfig.defaults.batchMiniModel},
      );

      await tester.tap(find.text('Small'));
      await tester.pumpAndSettle();

      expect(
        preferences.stored.defaultBatchModel,
        MistralConfig.defaults.batchSmallModel,
      );
    });

    testWidgets('the stored default batch model is selected on load',
        (tester) async {
      preferences.stored = const StoredPreferences(
        defaultBatchModel: 'voxtral-small-transcribe-3-0',
      );
      await pumpSettings(tester);
      await waitLoaded(tester);

      final segmented =
          tester.widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>));
      expect(
        segmented.selected,
        {MistralConfig.defaults.batchSmallModel},
      );
    });

    testWidgets('the language hint defaults to automatic detection and '
        'persists a pinned language', (tester) async {
      await pumpSettings(tester);
      await waitLoaded(tester);

      expect(find.text('Automatic detection'), findsOneWidget);

      await tester.tap(find.byType(DropdownButton<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('French').last);
      await tester.pumpAndSettle();

      expect(preferences.stored.languageHint, 'fr');
      expect(find.text('French'), findsOneWidget);
    });

    testWidgets('the stored language hint is shown on load', (tester) async {
      preferences.stored = const StoredPreferences(languageHint: 'de');
      await pumpSettings(tester);
      await waitLoaded(tester);

      expect(find.text('German'), findsOneWidget);
    });
  });
}
