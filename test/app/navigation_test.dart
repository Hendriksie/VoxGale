// Widget tests for the app navigation (task 6.1, design P2-D8): the live
// session screen's app bar actions push the file transcription, history,
// and settings screens — and nothing else (the debug action and the spike
// harness were removed in Phase 4). The missing-key error banner offers an
// open-settings action (the settings screen owns key entry since Phase 2).
// The controller, repository, preferences, and validator are test doubles
// — never real services.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:voxtral_live/app/file_transcription_screen.dart';
import 'package:voxtral_live/app/history_screen.dart';
import 'package:voxtral_live/app/live_session_screen.dart';
import 'package:voxtral_live/app/settings_screen.dart';
import 'package:voxtral_live/main.dart';
import 'package:voxtral_live/mistral/mistral.dart';
import 'package:voxtral_live/session/live_session_controller.dart';
import 'package:voxtral_live/session/session_providers.dart';

import 'fakes.dart';

class MockKeyValidationClient extends Mock implements KeyValidationClient {}

void main() {
  late MockKeyValidationClient validator;

  setUp(() {
    validator = MockKeyValidationClient();
    when(() => validator.validate(any())).thenAnswer((_) async {});
  });

  /// Pumps the app shell (home = the live session screen) with the given
  /// session state and test-double providers.
  Future<void> pumpApp(
    WidgetTester tester, {
    LiveSessionState? sessionState,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiKeyStoreProvider.overrideWith((ref) => FakeApiKeyStore()),
          sessionRepositoryProvider
              .overrideWith((ref) => InMemorySessionRepository()),
          preferencesRepositoryProvider
              .overrideWith((ref) => InMemoryPreferencesRepository()),
          keyValidationClientProvider.overrideWith((ref) => validator),
          liveSessionControllerProvider.overrideWith(
            () => FakeLiveSessionController(sessionState),
          ),
        ],
        child: const VoxtralLiveApp(),
      ),
    );
    await tester.pump();
  }

  testWidgets('the app bar actions push the file, history, and settings '
      'screens', (tester) async {
    await pumpApp(tester);

    // File mode.
    await tester.tap(find.byIcon(Icons.audio_file_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(FileTranscriptionScreen), findsOneWidget);
    expect(find.text('Pick an audio file'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // History.
    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();
    expect(find.byType(HistoryScreen), findsOneWidget);
    expect(find.text('No transcripts yet.'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Settings.
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('Mistral API key'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Back on the live session screen (home).
    expect(find.byType(LiveSessionScreen), findsOneWidget);
  });

  testWidgets('the missing-key error banner offers an open-settings action',
      (tester) async {
    await pumpApp(
      tester,
      sessionState: const LiveSessionState(
        phase: LiveSessionPhase.error,
        error: 'No API key saved. Add your Mistral API key to start a session.',
        missingApiKey: true,
      ),
    );

    expect(find.textContaining('No API key saved'), findsOneWidget);
    // The old debug-menu hint is gone — settings owns key entry now.
    expect(find.textContaining('debug menu'), findsNothing);

    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsOneWidget);
  });
}
