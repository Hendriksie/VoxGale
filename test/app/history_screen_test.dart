// Widget tests for the history screen (task 5.2, design P2-D6): the
// newest-first list with each entry's source (live session or file name),
// date, duration, and model; the text search; the empty states; delete-all;
// and opening an entry's detail view. The repository is an in-memory test
// double — never real storage.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxtral_live/app/history_detail_screen.dart';
import 'package:voxtral_live/app/history_screen.dart';
import 'package:voxtral_live/mistral/mistral.dart';
import 'package:voxtral_live/session/session_providers.dart';
import 'package:voxtral_live/storage/storage.dart';

import 'fakes.dart';

void main() {
  final config = MistralConfig.defaults;

  StoredSession liveSession({
    String id = 'live-1',
    DateTime? at,
  }) =>
      StoredSession(
        id: id,
        startedAt: at ?? DateTime(2026, 10, 25, 9, 0),
        durationSeconds: 65,
        model: config.realtimeModel,
        status: SessionStatus.finalized,
        billedAudioSeconds: 61,
        actualCost: 0.0081,
        language: 'en',
      );

  StoredSession fileSession({
    String id = 'file-1',
    DateTime? at,
  }) =>
      StoredSession(
        id: id,
        startedAt: at ?? DateTime(2026, 10, 26, 14, 32),
        durationSeconds: 30,
        model: config.batchMiniModel,
        status: SessionStatus.finalized,
        billedAudioSeconds: 30,
        actualCost: 0.00175,
        language: 'en',
        source: StoredSession.sourceFile,
        sourceFileName: 'interview.mp3',
      );

  List<StoredSegment> segments(String id, String text) => [
        StoredSegment(
          sessionId: id,
          order: 0,
          text: text,
          speakerLabel: 'speaker_1',
        ),
      ];

  Future<void> pumpHistory(
    WidgetTester tester,
    InMemorySessionRepository repository,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionRepositoryProvider.overrideWith((ref) => repository),
        ],
        child: const MaterialApp(home: HistoryScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists sessions newest-first with source, date, duration, and '
      'model', (tester) async {
    final repository = InMemorySessionRepository()
      ..add(liveSession(), segments('live-1', 'A live conversation'))
      ..add(fileSession(), segments('file-1', 'An imported file'));

    await pumpHistory(tester, repository);

    // Newest first: the file session (2026-10-26) before the live one
    // (2026-10-25).
    final sources = tester
        .widgetList<Text>(find.byType(ListTile).evaluate().isNotEmpty
            ? find.descendant(
                of: find.byType(ListView),
                matching: find.byType(Text),
              )
            : find.byType(Text))
        .map((t) => t.data)
        .toList();
    expect(sources.indexOf('interview.mp3'), lessThan(sources.indexOf('Live session')));
    expect(find.text('2026-10-26 14:32 · 0:30 · Mini'), findsOneWidget);
    expect(find.text('2026-10-25 09:00 · 1:05 · Realtime'), findsOneWidget);
    // The actual cost shows when known.
    expect(find.text('\$0.002'), findsOneWidget);
  });

  testWidgets('search filters the list by transcript text', (tester) async {
    final repository = InMemorySessionRepository()
      ..add(liveSession(), segments('live-1', 'the quick brown fox'))
      ..add(fileSession(), segments('file-1', 'a lazy dog'));

    await pumpHistory(tester, repository);

    await tester.enterText(find.byType(TextField), 'fox');
    await tester.pumpAndSettle();

    expect(find.text('Live session'), findsOneWidget);
    expect(find.text('interview.mp3'), findsNothing);
  });

  testWidgets('shows the empty state when there is no history', (tester) async {
    await pumpHistory(tester, InMemorySessionRepository());

    expect(find.text('No transcripts yet.'), findsOneWidget);
  });

  testWidgets('shows the no-match state for a search without results',
      (tester) async {
    final repository = InMemorySessionRepository()
      ..add(liveSession(), segments('live-1', 'A live conversation'));

    await pumpHistory(tester, repository);

    await tester.enterText(find.byType(TextField), 'zebra');
    await tester.pumpAndSettle();

    expect(find.text('No transcripts match your search.'), findsOneWidget);
  });

  testWidgets('delete-all asks for confirmation and empties the history',
      (tester) async {
    final repository = InMemorySessionRepository()
      ..add(liveSession(), segments('live-1', 'A live conversation'));

    await pumpHistory(tester, repository);

    await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete all'));
    await tester.pumpAndSettle();

    expect(repository.records, isEmpty);
    expect(find.text('No transcripts yet.'), findsOneWidget);
  });

  testWidgets('tapping an entry opens its detail view', (tester) async {
    final repository = InMemorySessionRepository()
      ..add(fileSession(), segments('file-1', 'An imported file'));

    await pumpHistory(tester, repository);

    await tester.tap(find.text('interview.mp3'));
    await tester.pumpAndSettle();

    expect(find.byType(HistoryDetailScreen), findsOneWidget);
    expect(find.text('An imported file'), findsOneWidget);
  });
}
