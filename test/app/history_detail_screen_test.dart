// Widget tests for the history detail screen (tasks 5.3-5.4, design
// P2-D6/D7): the metadata header (source, date, duration, model, actual
// cost), the speaker-labelled transcript, export (bottom sheet + the export
// action), delete (confirm + pop), and the pass re-offer card (shown with
// its estimate, running state, error state). The controller is a test double
// with a settable state — never real storage, file IO, or the live API (the
// controller's own load/re-offer logic, which does file IO, is covered by
// test/session/history_detail_controller_test.dart in plain tests where real
// IO completes).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxgale/app/history_detail_screen.dart';
import 'package:voxgale/app/transcript_export.dart';
import 'package:voxgale/mistral/mistral.dart';
import 'package:voxgale/session/history_detail_controller.dart';
import 'package:voxgale/session/session_providers.dart';
import 'package:voxgale/storage/storage.dart';

import 'fakes.dart';

void main() {
  final config = MistralConfig.defaults;

  final fileRecord = StoredSessionRecord(
    session: StoredSession(
      id: 'file-1',
      startedAt: DateTime(2026, 10, 26, 14, 32),
      durationSeconds: 30,
      model: config.batchMiniModel,
      status: SessionStatus.finalized,
      billedAudioSeconds: 30,
      actualCost: 0.00175,
      language: 'en',
      source: StoredSession.sourceFile,
      sourceFileName: 'interview.mp3',
    ),
    segments: const [
      StoredSegment(
        sessionId: 'file-1',
        order: 0,
        text: 'Hello there',
        speakerLabel: 'speaker_1',
        startSeconds: 0,
        endSeconds: 1.5,
      ),
      StoredSegment(
        sessionId: 'file-1',
        order: 1,
        text: 'Hi',
        speakerLabel: 'speaker_2',
        startSeconds: 1.5,
        endSeconds: 2.5,
      ),
    ],
  );

  final provisionalRecord = StoredSessionRecord(
    session: StoredSession(
      id: 'live-1',
      startedAt: DateTime(2026, 10, 25, 9, 0),
      durationSeconds: 30,
      model: config.realtimeModel,
      status: SessionStatus.provisional,
      billedAudioSeconds: 30,
      actualCost: 0.004,
      language: 'en',
      audioPath: '/tmp/live-1.wav',
    ),
    segments: const [
      StoredSegment(
        sessionId: 'live-1',
        order: 0,
        text: 'Provisional text',
      ),
    ],
  );

  /// The export action test double: records its calls.
  final exportCalls = <({StoredSessionRecord record, bool markdown})>[];

  setUp(() {
    exportCalls.clear();
  });

  /// Pumps the detail screen with the given (fake) controller state.
  Future<FakeHistoryDetailController> pumpDetail(
    WidgetTester tester,
    HistoryDetailState state, {
    String sessionId = 'file-1',
  }) async {
    final controller = FakeHistoryDetailController(sessionId, state);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historyDetailControllerProvider(sessionId)
              .overrideWith(() => controller),
          transcriptExportProvider.overrideWith(
            (ref) => (record, _, {required markdown}) async {
              exportCalls.add((record: record, markdown: markdown));
            },
          ),
        ],
        child: MaterialApp(home: HistoryDetailScreen(sessionId: sessionId)),
      ),
    );
    await tester.pump();
    return controller;
  }

  HistoryDetailState loaded(StoredSessionRecord record, {String? audioPath, double? estimate}) =>
      HistoryDetailState(
        loading: false,
        record: record,
        retainedAudioPath: audioPath,
        passEstimatedCost: estimate,
      );

  group('metadata and transcript (transcript-history spec)', () {
    testWidgets('shows the source, date, duration, model, actual cost, and '
        'the labelled transcript', (tester) async {
      await pumpDetail(tester, loaded(fileRecord));

      expect(find.text('interview.mp3'), findsOneWidget);
      expect(find.text('2026-10-26 14:32 · 0:30 · Mini'), findsOneWidget);
      expect(find.text('30 s billed · \$0.002'), findsOneWidget);
      expect(find.text('Hello there'), findsOneWidget);
      expect(find.text('Hi'), findsOneWidget);
      expect(find.text('speaker_1'), findsOneWidget);
      expect(find.text('speaker_2'), findsOneWidget);
    });

    testWidgets('a live session shows its source and model', (tester) async {
      await pumpDetail(tester, loaded(provisionalRecord), sessionId: 'live-1');

      expect(find.text('Live session'), findsOneWidget);
      expect(find.text('2026-10-25 09:00 · 0:30 · Realtime'), findsOneWidget);
    });

    testWidgets('shows a spinner while loading', (tester) async {
      await pumpDetail(tester, const HistoryDetailState());

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows a note when the record is gone', (tester) async {
      await pumpDetail(tester, const HistoryDetailState(loading: false));

      expect(find.text('This transcript is no longer available.'),
          findsOneWidget);
    });
  });

  group('delete (transcript-history spec)', () {
    testWidgets('asks for confirmation, deletes, and pops', (tester) async {
      final controller = FakeHistoryDetailController(
        'file-1',
        loaded(fileRecord),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            historyDetailControllerProvider('file-1')
                .overrideWith(() => controller),
            transcriptExportProvider.overrideWith(
              (ref) => (record, _, {required markdown}) async {},
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            const HistoryDetailScreen(sessionId: 'file-1'),
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
      expect(find.byType(HistoryDetailScreen), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(controller.calls, ['delete']);
      expect(find.byType(HistoryDetailScreen), findsNothing);
    });
  });

  group('export (transcript-history spec)', () {
    testWidgets('the bottom sheet offers both formats and exports the chosen '
        'one', (tester) async {
      await pumpDetail(tester, loaded(fileRecord));

      await tester.tap(find.byIcon(Icons.ios_share_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Plain text'), findsOneWidget);
      expect(find.text('Markdown'), findsOneWidget);

      await tester.tap(find.text('Markdown'));
      await tester.pumpAndSettle();

      expect(exportCalls, hasLength(1));
      expect(exportCalls.single.markdown, isTrue);
      expect(exportCalls.single.record.session.id, 'file-1');
    });

    testWidgets('exporting as plain text passes the format through',
        (tester) async {
      await pumpDetail(tester, loaded(fileRecord));

      await tester.tap(find.byIcon(Icons.ios_share_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plain text'));
      await tester.pumpAndSettle();

      expect(exportCalls.single.markdown, isFalse);
    });
  });

  group('pass re-offer (speaker-attribution spec)', () {
    testWidgets('is shown with its estimated cost and runs on tap',
        (tester) async {
      final controller = await pumpDetail(
        tester,
        loaded(
          provisionalRecord,
          audioPath: '/tmp/live-1.wav',
          estimate: 0.00175,
        ),
        sessionId: 'live-1',
      );

      expect(find.text('Add speaker labels'), findsOneWidget);
      expect(find.text('Post-session pass · est. \$0.002'), findsOneWidget);
      expect(find.text('Run'), findsOneWidget);

      await tester.tap(find.text('Run'));
      await tester.pump();

      expect(controller.calls, ['runPass']);
    });

    testWidgets('is hidden when there is no retained audio', (tester) async {
      await pumpDetail(tester, loaded(provisionalRecord), sessionId: 'live-1');

      expect(find.text('Add speaker labels'), findsNothing);
    });

    testWidgets('shows a spinner while the pass runs', (tester) async {
      await pumpDetail(
        tester,
        loaded(
          provisionalRecord,
          audioPath: '/tmp/live-1.wav',
          estimate: 0.00175,
        ).copyWith(passRunning: true),
        sessionId: 'live-1',
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Run'), findsNothing);
    });

    testWidgets('shows the pass failure with the offer kept for a retry',
        (tester) async {
      await pumpDetail(
        tester,
        loaded(
          provisionalRecord,
          audioPath: '/tmp/live-1.wav',
          estimate: 0.00175,
        ).copyWith(error: 'quota exceeded'),
        sessionId: 'live-1',
      );

      expect(find.text('quota exceeded'), findsOneWidget);
      expect(find.text('Run'), findsOneWidget);
      // The provisional transcript is still shown.
      expect(find.text('Provisional text'), findsOneWidget);
    });
  });
}
