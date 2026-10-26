// Tests for the transcript export (task 5.5, design P2-D6): the plain-text
// and Markdown builders over a stored session + segments, the speaker-label
// display mapping, and the share flow (temp file written with the expected
// content; the share sheet itself is unavailable off-device, which the
// default platform reports as a completed, unavailable result).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:voxtral_live/app/transcript_export.dart';
import 'package:voxtral_live/mistral/mistral.dart';
import 'package:voxtral_live/storage/storage.dart';

const config = MistralConfig.defaults;

final session = StoredSession(
  id: 'session-1',
  startedAt: DateTime(2026, 10, 26, 14, 32),
  durationSeconds: 65,
  model: config.batchMiniModel,
  status: SessionStatus.finalized,
  billedAudioSeconds: 61,
  actualCost: 0.0035,
  language: 'en',
  source: StoredSession.sourceFile,
  sourceFileName: 'interview.mp3',
);

final segments = <StoredSegment>[
  const StoredSegment(
    sessionId: 'session-1',
    order: 0,
    text: 'Hello there',
    speakerLabel: 'speaker_1',
    startSeconds: 0,
    endSeconds: 1.5,
  ),
  const StoredSegment(
    sessionId: 'session-1',
    order: 1,
    text: 'Hi',
    speakerLabel: 'speaker_2',
    startSeconds: 1.5,
    endSeconds: 2.5,
  ),
];

void main() {
  group('speakerLabelForDisplay', () {
    test('maps generic labels to display form', () {
      expect(speakerLabelForDisplay('speaker_1'), 'Speaker 1');
      expect(speakerLabelForDisplay('speaker_12'), 'Speaker 12');
    });

    test('passes enrolled names through unchanged', () {
      expect(speakerLabelForDisplay('Alice'), 'Alice');
    });
  });

  group('transcriptToPlainText (transcript-history spec)', () {
    test('includes the header and labelled, timestamped segments', () {
      final text = transcriptToPlainText(session, segments, config);

      expect(text, contains('Voxtral Live transcript'));
      expect(text, contains('2026-10-26 14:32 · 1:05 · Mini · File: interview.mp3'));
      expect(text, contains('[0:00] Speaker 1: Hello there'));
      expect(text, contains('[0:02] Speaker 2: Hi'));
    });

    test('renders segments without labels or timestamps as plain text', () {
      const plain = StoredSegment(sessionId: 's', order: 0, text: 'Just text');

      final text = transcriptToPlainText(session, const [plain], config);

      expect(text, contains('Just text'));
      expect(text, isNot(contains('[')));
      expect(text, isNot(contains('Speaker')));
    });

    test('shows a live session as the source', () {
      final live = StoredSession(
        id: 's',
        startedAt: DateTime(2026, 10, 26),
        durationSeconds: 10,
        model: config.realtimeModel,
        status: SessionStatus.finalized,
      );

      final text = transcriptToPlainText(live, const [], config);

      expect(text, contains('Live session'));
      expect(text, contains('Realtime'));
    });
  });

  group('transcriptToMarkdown (transcript-history spec)', () {
    test('includes the heading, metadata, and labelled segments', () {
      final markdown = transcriptToMarkdown(session, segments, config);

      expect(markdown, contains('# Transcript — 2026-10-26 14:32'));
      expect(
        markdown,
        contains('_1:05 · Mini · File: interview.mp3_'),
      );
      expect(markdown, contains('**Speaker 1** (0:00)'));
      expect(markdown, contains('Hello there'));
      expect(markdown, contains('**Speaker 2** (0:02)'));
      expect(markdown, contains('Hi'));
    });

    test('separates segments with blank lines', () {
      final markdown = transcriptToMarkdown(session, segments, config);

      expect(
        markdown,
        contains('Hello there\n\n**Speaker 2** (0:02)\nHi'),
      );
    });
  });

  group('shareTranscriptExport', () {
    test('writes the Markdown export to a temp file and shares it',
        () async {
      final record = StoredSessionRecord(session: session, segments: segments);
      ShareParams? shared;

      await shareTranscriptExport(
        record,
        config,
        markdown: true,
        share: (params) async {
          shared = params;
          return ShareResult(
            'dev.fluttercommunity.plus/share/unavailable',
            ShareResultStatus.unavailable,
          );
        },
      );

      final file = File(
        '${Directory.systemTemp.path}/voxtral-transcript-session-1.md',
      );
      addTearDown(() async {
        if (await file.exists()) await file.delete();
      });
      expect(await file.exists(), isTrue);
      final content = await file.readAsString();
      expect(content, contains('# Transcript — 2026-10-26 14:32'));
      expect(content, contains('**Speaker 1** (0:00)'));
      // The share sheet is invoked with the exported file.
      expect(shared, isNotNull);
      expect(shared!.files, hasLength(1));
      expect(shared!.files!.single.path, file.path);
    });

    test('writes the plain-text export to a temp file and shares it',
        () async {
      final record = StoredSessionRecord(session: session, segments: segments);
      ShareParams? shared;

      await shareTranscriptExport(
        record,
        config,
        markdown: false,
        share: (params) async {
          shared = params;
          return ShareResult(
            'dev.fluttercommunity.plus/share/unavailable',
            ShareResultStatus.unavailable,
          );
        },
      );

      final file = File(
        '${Directory.systemTemp.path}/voxtral-transcript-session-1.txt',
      );
      addTearDown(() async {
        if (await file.exists()) await file.delete();
      });
      expect(await file.exists(), isTrue);
      final content = await file.readAsString();
      expect(content, contains('[0:00] Speaker 1: Hello there'));
      expect(shared!.files!.single.path, file.path);
    });
  });
}
