// Tests for the history detail controller (tasks 5.3-5.4, design P2-D6/D7):
// the load (the record; the pass re-offer with its estimated cost for a
// provisional session with retained audio — and hidden for a final session,
// no audio, or a stale audio path), running the re-offered pass (replaces
// the transcript, deletes the audio, removes the offer; a failure keeps the
// provisional transcript with a retry), and delete. Plain tests (not widget
// tests) because the controller does real file IO — the re-offer checks the
// audio file's existence and the pass reads it. The repository and the batch
// client are test doubles — never real storage, never the live API.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:voxtral_live/mistral/mistral.dart';
import 'package:voxtral_live/session/history_detail_controller.dart';
import 'package:voxtral_live/session/session_providers.dart';
import 'package:voxtral_live/storage/storage.dart';

class MockBatchTranscriptionClient extends Mock
    implements BatchTranscriptionClient {}

class InMemorySessionRepository implements SessionRepository {
  final Map<String, StoredSessionRecord> records = {};

  void add(StoredSession session, List<StoredSegment> segments) {
    records[session.id] = StoredSessionRecord(session: session, segments: segments);
  }

  @override
  Future<void> saveSession(
    StoredSession session,
    List<StoredSegment> segments,
  ) async {
    add(session, segments);
  }

  @override
  Future<StoredSessionRecord?> loadSession(String id) async => records[id];

  @override
  Future<void> replaceTranscript(
    String sessionId,
    List<StoredSegment> segments, {
    required int billedAudioSeconds,
    required double actualCost,
  }) async {
    final record = records[sessionId];
    if (record == null) {
      throw ArgumentError.value(sessionId, 'sessionId', 'Unknown session id');
    }
    final session = record.session;
    records[sessionId] = StoredSessionRecord(
      session: StoredSession(
        id: session.id,
        startedAt: session.startedAt,
        durationSeconds: session.durationSeconds,
        model: session.model,
        status: SessionStatus.finalized,
        billedAudioSeconds: billedAudioSeconds,
        actualCost: actualCost,
        language: session.language,
        audioPath: session.audioPath,
        source: session.source,
        sourceFileName: session.sourceFileName,
      ),
      segments: segments,
    );
  }

  @override
  Future<void> deleteSession(String id) async {
    records.remove(id);
  }

  @override
  Future<List<StoredSession>> listSessions({String? searchQuery}) async {
    final sessions = records.values.map((r) => r.session).toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return sessions;
  }

  @override
  Future<void> deleteAllSessions() async {
    records.clear();
  }

  @override
  Future<void> close() async {}
}

class InMemoryPreferencesRepository implements PreferencesRepository {
  StoredPreferences stored = const StoredPreferences();

  @override
  Future<StoredPreferences> loadPreferences() async => stored;

  @override
  Future<void> savePreferences(StoredPreferences preferences) async {
    stored = preferences;
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      BatchTranscriptionRequest(
        model: 'model',
        audioBytes: Uint8List(0),
        fileName: 'file.wav',
      ),
    );
    registerFallbackValue(<StoredSegment>[]);
  });

  const config = MistralConfig.defaults;
  late Directory tempDir;
  late InMemorySessionRepository repository;
  late MockBatchTranscriptionClient batchClient;
  late ProviderContainer container;

  HistoryDetailState state(String sessionId) =>
      container.read(historyDetailControllerProvider(sessionId));

  HistoryDetailController controller(String sessionId) {
    // The provider is an auto-dispose family: a listener keeps it (and its
    // async load) alive for the test.
    container.listen(
      historyDetailControllerProvider(sessionId),
      (previous, next) {},
    );
    return container.read(historyDetailControllerProvider(sessionId).notifier);
  }

  /// Lets the event loop run until [condition] holds (with a timeout).
  Future<void> waitFor(String sessionId, bool Function() condition) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(condition(), isTrue);
  }

  StoredSession provisionalSession(String id, String? audioPath) =>
      StoredSession(
        id: id,
        startedAt: DateTime(2026, 10, 25, 9, 0),
        durationSeconds: 30,
        model: config.realtimeModel,
        status: SessionStatus.provisional,
        billedAudioSeconds: 30,
        actualCost: 0.004,
        language: 'en',
        audioPath: audioPath,
      );

  StoredSession finalSession(String id) => StoredSession(
        id: id,
        startedAt: DateTime(2026, 10, 26, 14, 32),
        durationSeconds: 30,
        model: config.batchMiniModel,
        status: SessionStatus.finalized,
        billedAudioSeconds: 30,
        actualCost: 0.00175,
        language: 'en',
        source: StoredSession.sourceFile,
        sourceFileName: 'interview.mp3',
      );

  List<StoredSegment> segments(String id) => [
        StoredSegment(sessionId: id, order: 0, text: 'Provisional text'),
      ];

  /// Writes a session WAV with [dataBytes] of audio data and returns its
  /// path (the pass reads it for the duration and the upload).
  Future<String> writeWav(String name, int dataBytes) async {
    final file = File('${tempDir.path}/$name');
    // The 44-byte header [WavFileWriter] writes, then zeroed audio data.
    await file.writeAsBytes(List<int>.filled(44 + dataBytes, 0));
    return file.path;
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('voxtral_history_ctrl_test');
    repository = InMemorySessionRepository();
    batchClient = MockBatchTranscriptionClient();
    container = ProviderContainer(
      overrides: [
        sessionRepositoryProvider.overrideWith((ref) => repository),
        preferencesRepositoryProvider
            .overrideWith((ref) => InMemoryPreferencesRepository()),
        batchTranscriptionClientProvider
            .overrideWith((ref) async => batchClient),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await tempDir.delete(recursive: true);
  });

  group('load (design P2-D6/D7)', () {
    test('loads the record', () async {
      repository.add(finalSession('file-1'), segments('file-1'));

      controller('file-1');
      await waitFor('file-1', () => !state('file-1').loading);

      expect(state('file-1').record!.session.id, 'file-1');
      expect(state('file-1').retainedAudioPath, isNull);
    });

    test('a final session has no re-offer', () async {
      repository.add(finalSession('file-1'), segments('file-1'));

      controller('file-1');
      await waitFor('file-1', () => !state('file-1').loading);

      expect(state('file-1').retainedAudioPath, isNull);
      expect(state('file-1').passEstimatedCost, isNull);
    });

    test('a provisional session with retained audio offers the pass with '
        'its estimated cost', () async {
      final audioPath = await writeWav('live-1.wav', 32000 * 30);
      repository.add(provisionalSession('live-1', audioPath), segments('live-1'));

      controller('live-1');
      await waitFor('live-1', () => !state('live-1').loading);

      expect(state('live-1').retainedAudioPath, audioPath);
      // 30 s / 60 × the Mini rate.
      expect(state('live-1').passEstimatedCost,
          closeTo(30 / 60 * config.batchMiniRatePerMinute, 1e-12));
    });

    test('a provisional session without an audio path has no re-offer',
        () async {
      repository.add(provisionalSession('live-1', null), segments('live-1'));

      controller('live-1');
      await waitFor('live-1', () => !state('live-1').loading);

      expect(state('live-1').retainedAudioPath, isNull);
    });

    test('a stale audio path (the file is gone) has no re-offer', () async {
      // A successful pass leaves a stale audioPath in the row; the offer
      // checks the file's existence, not just the stored path.
      repository.add(
        provisionalSession('live-1', '${tempDir.path}/gone.wav'),
        segments('live-1'),
      );

      controller('live-1');
      await waitFor('live-1', () => !state('live-1').loading);

      expect(state('live-1').retainedAudioPath, isNull);
    });

    test('an unknown session id loads as gone', () async {
      controller('missing');
      await waitFor('missing', () => !state('missing').loading);

      expect(state('missing').record, isNull);
    });
  });

  group('runPass (speaker-attribution spec)', () {
    test('replaces the transcript, deletes the audio, and removes the offer',
        () async {
      final audioPath = await writeWav('live-1.wav', 32000 * 30);
      repository.add(provisionalSession('live-1', audioPath), segments('live-1'));
      when(() => batchClient.transcribe(any())).thenAnswer(
        (_) async => const BatchTranscriptionResult(
          text: 'Hello world',
          segments: [
            TranscriptSegment(
              text: 'Hello world',
              speakerId: 'speaker_1',
              start: 0,
              end: 2,
            ),
          ],
          language: 'en',
          model: 'voxtral-mini-transcribe-3-0',
          usage: Usage(promptAudioSeconds: 30),
        ),
      );

      controller('live-1');
      await waitFor('live-1', () => !state('live-1').loading);
      await controller('live-1').runPass();
      await waitFor('live-1', () => !state('live-1').passRunning);

      // The transcript is replaced and the session is final; the offer is
      // gone.
      expect(state('live-1').record!.session.status, SessionStatus.finalized);
      expect(state('live-1').record!.segments.single.speakerLabel, 'speaker_1');
      expect(state('live-1').retainedAudioPath, isNull);
      // The audio is deleted after the successful pass.
      expect(await File(audioPath).exists(), isFalse);
    });

    test('a failure keeps the provisional transcript with an error and a '
        'retry succeeds', () async {
      final audioPath = await writeWav('live-1.wav', 32000 * 30);
      repository.add(provisionalSession('live-1', audioPath), segments('live-1'));
      var calls = 0;
      when(() => batchClient.transcribe(any())).thenAnswer((_) async {
        calls++;
        if (calls == 1) {
          throw MistralApiException('quota exceeded');
        }
        return const BatchTranscriptionResult(
          text: 'Recovered',
          segments: [
            TranscriptSegment(
              text: 'Recovered',
              speakerId: 'speaker_1',
              start: 0,
              end: 1,
            ),
          ],
          language: 'en',
          model: 'voxtral-mini-transcribe-3-0',
          usage: Usage(promptAudioSeconds: 30),
        );
      });

      controller('live-1');
      await waitFor('live-1', () => !state('live-1').loading);
      await controller('live-1').runPass();

      // The provisional transcript is preserved; the error shows; the offer
      // remains for a retry.
      expect(state('live-1').hasError, isTrue);
      expect(state('live-1').error, 'quota exceeded');
      expect(state('live-1').record!.session.status, SessionStatus.provisional);
      expect(state('live-1').retainedAudioPath, audioPath);
      expect(await File(audioPath).exists(), isTrue);

      // A retry succeeds.
      await controller('live-1').runPass();
      await waitFor('live-1', () => !state('live-1').passRunning);

      expect(state('live-1').hasError, isFalse);
      expect(state('live-1').record!.session.status, SessionStatus.finalized);
      expect(state('live-1').retainedAudioPath, isNull);
    });

    test('is a no-op without retained audio', () async {
      repository.add(provisionalSession('live-1', null), segments('live-1'));

      controller('live-1');
      await waitFor('live-1', () => !state('live-1').loading);
      await controller('live-1').runPass();

      verifyNever(() => batchClient.transcribe(any()));
      expect(state('live-1').record!.session.status, SessionStatus.provisional);
    });
  });

  group('delete (transcript-history spec)', () {
    test('removes the transcript from the repository', () async {
      repository.add(finalSession('file-1'), segments('file-1'));

      controller('file-1');
      await waitFor('file-1', () => !state('file-1').loading);
      await controller('file-1').delete();

      expect(repository.records, isEmpty);
      expect(await repository.loadSession('file-1'), isNull);
    });
  });
}
