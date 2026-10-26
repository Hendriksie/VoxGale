// Widget tests for the file transcription screen (task 4.3, design P2-D1):
// the idle pick action, the missing-key banner with its open-settings path,
// the picked view (file, model choice, estimate), the running progress (no
// partial text — the batch API is one-shot), the done result with actual
// usage, and the error state keeping the picked file. The controller is a
// test double — never real services, never the live API.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:voxtral_live/app/file_transcription_screen.dart';
import 'package:voxtral_live/app/settings_screen.dart';
import 'package:voxtral_live/app/transcript_widgets.dart';
import 'package:voxtral_live/mistral/mistral.dart';
import 'package:voxtral_live/session/file_transcription_controller.dart';
import 'package:voxtral_live/session/session_models.dart';
import 'package:voxtral_live/session/session_providers.dart';

import 'fakes.dart';

class MockKeyValidationClient extends Mock implements KeyValidationClient {}

void main() {
  late MockKeyValidationClient validator;

  setUp(() {
    validator = MockKeyValidationClient();
    when(() => validator.validate(any())).thenAnswer((_) async {});
  });

  /// Pumps the file transcription screen with the given (fake) controller
  /// state. The settings providers are overridden too — the missing-key
  /// banner pushes the settings screen.
  Future<FakeFileTranscriptionController> pumpScreen(
    WidgetTester tester,
    FileTranscriptionState state,
  ) async {
    final controller = FakeFileTranscriptionController(state);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fileTranscriptionControllerProvider.overrideWith(() => controller),
          apiKeyStoreProvider.overrideWith((ref) => FakeApiKeyStore()),
          keyValidationClientProvider.overrideWith((ref) => validator),
          preferencesRepositoryProvider
              .overrideWith((ref) => InMemoryPreferencesRepository()),
        ],
        child: const MaterialApp(home: FileTranscriptionScreen()),
      ),
    );
    await tester.pump();
    return controller;
  }

  FileTranscriptionState pickedState({
    String fileName = 'interview.mp3',
    int durationSeconds = 65,
    bool durationKnown = true,
    String? selectedModel,
    double estimatedCost = 0.0038,
  }) =>
      FileTranscriptionState(
        phase: FileTranscriptionPhase.picked,
        fileName: fileName,
        durationSeconds: durationSeconds,
        durationKnown: durationKnown,
        selectedModel:
            selectedModel ?? MistralConfig.defaults.batchMiniModel,
        estimatedCost: estimatedCost,
      );

  group('idle (file-transcription spec: import an audio file)', () {
    testWidgets('shows the pick action and calls pick', (tester) async {
      final controller = await pumpScreen(
        tester,
        const FileTranscriptionState(),
      );

      expect(find.text('Pick an audio file'), findsOneWidget);
      expect(find.text('No API key saved.'), findsNothing);

      await tester.tap(find.text('Pick an audio file'));
      await tester.pump();

      expect(controller.calls, ['pick']);
    });

    testWidgets('shows a missing-key banner with an open-settings action',
        (tester) async {
      await pumpScreen(
        tester,
        const FileTranscriptionState(missingApiKey: true),
      );

      expect(find.textContaining('No API key saved'), findsOneWidget);

      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);
    });
  });

  group('picked (per-file model choice + pre-upload estimate)', () {
    testWidgets('shows the file, its duration, the model choice, and the '
        'estimate', (tester) async {
      await pumpScreen(tester, pickedState());

      expect(find.text('interview.mp3'), findsOneWidget);
      expect(find.text('1:05'), findsOneWidget);
      expect(find.text('Estimated cost: \$0.004'), findsOneWidget);

      // Mini is selected (the default model).
      final segmented = tester
          .widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>));
      expect(segmented.selected, {MistralConfig.defaults.batchMiniModel});
    });

    testWidgets('choosing the model, transcribing, and re-picking call the '
        'controller', (tester) async {
      final controller = await pumpScreen(tester, pickedState());

      await tester.tap(find.text('Small'));
      await tester.pump();
      await tester.tap(find.text('Transcribe'));
      await tester.pump();
      await tester.tap(find.text('Choose a different file'));
      await tester.pump();

      expect(controller.calls, [
        'setModel:${MistralConfig.defaults.batchSmallModel}',
        'transcribe',
        'pick',
      ]);
    });

    testWidgets('an unknown duration shows the accruing-estimate note',
        (tester) async {
      await pumpScreen(tester, pickedState(durationKnown: false, durationSeconds: 0));

      expect(find.text('Duration unknown'), findsOneWidget);
      expect(
        find.text('The estimate accrues while the transcription runs.'),
        findsOneWidget,
      );
    });
  });

  group('running (progress, no partial text)', () {
    testWidgets('shows the progress with elapsed time and the running '
        'estimate', (tester) async {
      await pumpScreen(
        tester,
        const FileTranscriptionState(
          phase: FileTranscriptionPhase.running,
          fileName: 'interview.mp3',
          elapsedSeconds: 12,
          estimatedCost: 0.0007,
          selectedModel: 'voxtral-mini-transcribe-3-0',
        ),
      );

      expect(find.text('Transcribing interview.mp3…'), findsOneWidget);
      expect(find.text('0:12 · est. \$0.001'), findsOneWidget);
      // The batch API is one-shot: no partial transcript text is shown.
      expect(find.byType(TranscriptView), findsNothing);
    });
  });

  group('done (result + actual usage, saved to history)', () {
    testWidgets('shows the labelled result and the billed usage',
        (tester) async {
      await pumpScreen(
        tester,
        const FileTranscriptionState(
          phase: FileTranscriptionPhase.done,
          fileName: 'interview.mp3',
          durationSeconds: 30,
          turns: [
            TranscriptTurn(
              speakerLabel: 'speaker_1',
              text: 'Hello there',
              isProvisional: false,
            ),
            TranscriptTurn(
              speakerLabel: 'speaker_2',
              text: 'Hi',
              isProvisional: false,
            ),
          ],
          billedAudioSeconds: 30,
          actualCost: 0.00175,
        ),
      );

      expect(find.text('Hello there'), findsOneWidget);
      expect(find.text('Hi'), findsOneWidget);
      expect(find.text('speaker_1'), findsOneWidget);
      expect(find.text('30 s billed · \$0.002'), findsOneWidget);
      expect(find.text('Saved to history.'), findsOneWidget);
    });

    testWidgets('an empty result shows the empty-transcript note',
        (tester) async {
      await pumpScreen(
        tester,
        const FileTranscriptionState(
          phase: FileTranscriptionPhase.done,
          fileName: 'quiet.mp3',
        ),
      );

      expect(find.text('The transcript is empty.'), findsOneWidget);
    });

    testWidgets('done pops the screen; another file re-picks', (tester) async {
      final controller = FakeFileTranscriptionController(
        const FileTranscriptionState(
          phase: FileTranscriptionPhase.done,
          fileName: 'interview.mp3',
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            fileTranscriptionControllerProvider.overrideWith(() => controller),
            apiKeyStoreProvider.overrideWith((ref) => FakeApiKeyStore()),
            keyValidationClientProvider.overrideWith((ref) => validator),
            preferencesRepositoryProvider
                .overrideWith((ref) => InMemoryPreferencesRepository()),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const FileTranscriptionScreen(),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(FileTranscriptionScreen), findsOneWidget);

      await tester.tap(find.text('Transcribe another file'));
      await tester.pump();
      expect(controller.calls, ['pick']);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(FileTranscriptionScreen), findsNothing);
    });
  });

  group('error (the picked file is kept)', () {
    testWidgets('shows the error, the file, and the retry action',
        (tester) async {
      final controller = await pumpScreen(
        tester,
        const FileTranscriptionState(
          phase: FileTranscriptionPhase.error,
          fileName: 'interview.mp3',
          error: 'The file is too large for the API.',
          selectedModel: 'voxtral-mini-transcribe-3-0',
        ),
      );

      expect(find.text('The file transcription failed'), findsOneWidget);
      expect(find.text('The file is too large for the API.'), findsOneWidget);
      expect(find.text('interview.mp3'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(controller.calls, ['transcribe']);

      await tester.tap(find.text('Choose a different file'));
      await tester.pump();
      expect(controller.calls, ['transcribe', 'pick']);
    });
  });
}
