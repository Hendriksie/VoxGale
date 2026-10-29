// Widget tests for the settings screen (task 3.2, design P2-D4, Phase 3
// group 2): the key status (saved/not saved — the value is never displayed),
// save-with-validation (invalid key → the shared auth error banner, not
// saved; valid key → saved; unreachable API → the shared no-network banner
// with a retry action), key removal, and the persisted preferences (default
// batch model, language hint). The validator, key store, and preferences
// repository are test doubles — never real services, never the live API.
//
// Also the Updates section's widget tests (change 2026-10-29-update-tracker,
// tasks 6.3-6.4, design decisions 14-16): the installed version row, the
// manual "Check for updates" action (exactly one check, the up-to-date
// confirmation with no dialog, the disabled button + progress indicator
// while a check runs, the error banner with retry on failure, and the
// persisted last-check time advancing past the throttle), and the update
// dialog a manual check presents over this screen through the home screen's
// listener (even when the version was already notified and while a session
// is recording). Every update-tracker provider is overridden with the fakes
// — no test here hits the live GitHub API or a platform channel.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:voxgale/app/error_states.dart';
import 'package:voxgale/app/live_session_screen.dart';
import 'package:voxgale/app/settings_screen.dart';
import 'package:voxgale/mistral/mistral.dart';
import 'package:voxgale/session/live_session_controller.dart';
import 'package:voxgale/session/session_providers.dart';
import 'package:voxgale/storage/storage.dart';
import 'package:voxgale/update/update_check_client.dart';
import 'package:voxgale/update/update_providers.dart';

import '../update/fakes.dart';
import 'fakes.dart';

class MockKeyValidationClient extends Mock implements KeyValidationClient {}

/// A [FakeUpdateCheckClient] whose fetch is gated on a completer, so a test
/// can hold a manual check in flight.
class GatedUpdateCheckClient extends FakeUpdateCheckClient {
  final Completer<UpdateInfo?> gate = Completer<UpdateInfo?>();

  @override
  Future<UpdateInfo?> fetchLatestRelease() {
    callCount++;
    return gate.future;
  }
}

void main() {
  late FakeApiKeyStore apiKeyStore;
  late MockKeyValidationClient validator;
  late InMemoryPreferencesRepository preferences;

  /// A release of [version] on GitHub (the pinned repo's release page).
  UpdateInfo release(String version) => UpdateInfo(
        version: version,
        releasePageUrl: Uri.parse(
            'https://github.com/Hendriksie/VoxGale/releases/tag/v$version'),
      );

  /// Pumps the settings screen with the update tracker's fakes wired in (the
  /// Updates section watches the update controller directly — design
  /// decision 14 — so the widget tests stay offline and never touch a
  /// platform channel, design decision 11).
  Future<void> pumpSettings(
    WidgetTester tester, {
    FakeUpdateCheckClient? updateCheckClient,
    InMemoryUpdateStateRepository? updateStateRepository,
    FakeAppVersionReader? appVersionReader,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiKeyStoreProvider.overrideWith((ref) => apiKeyStore),
          keyValidationClientProvider.overrideWith((ref) => validator),
          preferencesRepositoryProvider.overrideWith((ref) => preferences),
          updateCheckClientProvider.overrideWith(
            (ref) => updateCheckClient ?? FakeUpdateCheckClient(),
          ),
          appVersionReaderProvider.overrideWith(
            (ref) => appVersionReader ?? FakeAppVersionReader('1.2.0'),
          ),
          urlOpenerProvider.overrideWith((ref) => FakeUrlOpener()),
          updateStateRepositoryProvider.overrideWith(
            (ref) => updateStateRepository ?? InMemoryUpdateStateRepository(),
          ),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();
  }

  /// Scrolls the settings list until the "Check for updates" button is on
  /// screen (the Updates section sits below the API-key and preferences
  /// sections). Fixed pumps only: with a session recording, the home screen's
  /// recording indicator pulses forever, so pumpAndSettle would never return.
  Future<void> revealCheckButton(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Check for updates'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
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

    testWidgets('the keep-screen-on toggle defaults to off and persists a '
        'toggle (change 2026-10-29-keep-screen-on-during-sessions)',
        (tester) async {
      await pumpSettings(tester);
      await waitLoaded(tester);

      final toggle = find.byType(SwitchListTile);
      expect(find.text('Keep screen on during sessions'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      expect(preferences.stored.keepScreenOn, isTrue);
    });

    testWidgets('the stored keep-screen-on preference is shown on load',
        (tester) async {
      preferences.stored = const StoredPreferences(keepScreenOn: true);
      await pumpSettings(tester);
      await waitLoaded(tester);

      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
    });
  });

  group('updates section (update-tracker spec, tasks 6.3-6.4)', () {
    testWidgets('shows the installed version', (tester) async {
      await pumpSettings(
        tester,
        appVersionReader: FakeAppVersionReader('1.2.0'),
      );
      await waitLoaded(tester);

      expect(find.text('Updates'), findsOneWidget);
      expect(find.text('VoxGale v1.2.0'), findsOneWidget);
      expect(find.text('Check for updates'), findsOneWidget);
    });

    testWidgets('tapping "Check for updates" runs exactly one check and, '
        'when current, shows the up-to-date confirmation with no dialog',
        (tester) async {
      final client = FakeUpdateCheckClient();
      client.result = release('1.2.0'); // same as the fake installed version
      await pumpSettings(tester, updateCheckClient: client);
      await waitLoaded(tester);

      await revealCheckButton(tester);
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();

      expect(client.callCount, 1);
      expect(find.text("You're up to date."), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Update available'), findsNothing);
    });

    testWidgets('while a check runs the button is disabled and the progress '
        'indicator shows', (tester) async {
      final client = GatedUpdateCheckClient();
      await pumpSettings(tester, updateCheckClient: client);
      await waitLoaded(tester);

      await revealCheckButton(tester);
      await tester.tap(find.text('Check for updates'));
      await tester.pump();

      expect(client.callCount, 1);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      FilledButton button() => tester.widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Check for updates'),
          );
      expect(button().onPressed, isNull);

      client.gate.complete(release('1.2.0'));
      await tester.pumpAndSettle();

      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text("You're up to date."), findsOneWidget);
      expect(button().onPressed, isNotNull);
    });

    testWidgets('a failed check shows the error banner, and its retry '
        'action re-runs the check', (tester) async {
      final client = FakeUpdateCheckClient();
      // A failure, then a well-formed response for the retry.
      client.queue.addAll([null, release('1.2.0')]);
      await pumpSettings(tester, updateCheckClient: client);
      await waitLoaded(tester);

      await revealCheckButton(tester);
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();

      // The update check fails only when GitHub is unreachable, so the
      // failure surfaces as a no-network failure (design decision 16).
      expect(client.callCount, 1);
      expect(find.byType(ErrorBanner), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
      expect(
        find.text(
          'Could not check for updates. Check your connection and try again.',
        ),
        findsOneWidget,
      );

      // The banner renders above the button, so scroll it into view first.
      await tester.ensureVisible(find.text('Retry'));
      await tester.pump();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(client.callCount, 2);
      expect(find.byType(ErrorBanner), findsNothing);
      expect(find.text("You're up to date."), findsOneWidget);
    });

    testWidgets('the manual check advances the persisted last-check time '
        '(it bypasses the throttle)', (tester) async {
      final client = FakeUpdateCheckClient();
      client.result = release('1.2.0');
      // A check an hour ago — inside the 24-hour throttle window, so the
      // automatic start check would not run; the manual check must.
      final recentMs =
          DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
      final updateState = InMemoryUpdateStateRepository()
        ..stored = StoredUpdateState(lastCheckAtMs: recentMs);
      await pumpSettings(
        tester,
        updateCheckClient: client,
        updateStateRepository: updateState,
      );
      await waitLoaded(tester);

      await revealCheckButton(tester);
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();

      expect(client.callCount, 1);
      expect(updateState.stored.lastCheckAtMs, greaterThan(recentMs));
      // A well-formed response advances the time; no version was notified.
      expect(updateState.stored.lastNotifiedVersion, isNull);
    });

    testWidgets('a manual check that finds a newer version shows the update '
        'dialog over this screen — even when that version was already '
        'notified and while a session is recording', (tester) async {
      final client = FakeUpdateCheckClient();
      final urlOpener = FakeUrlOpener();
      final updateState = InMemoryUpdateStateRepository()
        ..stored = const StoredUpdateState(lastNotifiedVersion: '1.3.0');
      client.result = release('1.3.0');
      // The home screen's dialog listener is in the tree beneath the pushed
      // settings route; a session is recording (the explicit manual check
      // overrides the recording gate — spec: "Report the outcome of a
      // manual check").
      await tester.pumpWidget(appWithStore(
        FakeApiKeyStore(),
        sessionController: FakeLiveSessionController(
          const LiveSessionState(phase: LiveSessionPhase.active),
        ),
        updateClient: client,
        updateStateRepository: updateState,
        urlOpener: urlOpener,
        appVersionReader: FakeAppVersionReader('1.2.0'),
      ));
      await tester.pump();
      // Await the start check the home screen fired (suppressed: the version
      // was already notified and a session is recording).
      await ProviderScope.containerOf(
        tester.element(find.byType(LiveSessionScreen)),
      ).read(updateCheckOnStartProvider.future);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(AlertDialog), findsNothing);

      // Open Settings from the home screen's app bar.
      await tester.tap(find.byTooltip('Settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(SettingsScreen), findsOneWidget);

      await revealCheckButton(tester);
      await tester.tap(find.text('Check for updates'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // The dialog is presented on the root navigator, over the settings
      // route, naming both versions.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Update available'), findsOneWidget);
      expect(
        find.text('VoxGale v1.3.0 is available (you have v1.2.0).'),
        findsOneWidget,
      );
      expect(find.text('Later'), findsOneWidget);
      expect(find.text('Open release'), findsOneWidget);
    });
  });
}
