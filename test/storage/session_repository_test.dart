import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voxtral_live/storage/storage.dart';

void main() {
  late AppDatabase db;
  late DriftSessionRepository repository;

  setUp(() {
    db = AppDatabase.memory();
    repository = DriftSessionRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  final startedAt = DateTime.utc(2026, 10, 23, 10, 0, 0);

  StoredSession session({
    String id = 'session-1',
    SessionStatus status = SessionStatus.provisional,
    String? audioPath,
    int? billedAudioSeconds = 61,
    double? actualCost = 0.0123,
  }) {
    return StoredSession(
      id: id,
      startedAt: startedAt,
      durationSeconds: 65,
      model: 'voxtral-mini-transcribe-realtime-3-0',
      status: status,
      billedAudioSeconds: billedAudioSeconds,
      actualCost: actualCost,
      language: 'en',
      audioPath: audioPath,
    );
  }

  List<StoredSegment> segments(String sessionId) {
    return [
      StoredSegment(
        sessionId: sessionId,
        order: 0,
        text: 'Hello ',
        speakerLabel: null,
        startSeconds: null,
        endSeconds: null,
      ),
      StoredSegment(
        sessionId: sessionId,
        order: 1,
        text: 'world',
        speakerLabel: 'speaker_1',
        startSeconds: 1.5,
        endSeconds: 2.5,
      ),
    ];
  }

  test('saves a finalized session with its segments and loads it back by id',
      () async {
    final saved = session(audioPath: '/tmp/sessions/session-1.wav');
    final savedSegments = segments(saved.id);

    await repository.saveSession(saved, savedSegments);

    final loaded = await repository.loadSession(saved.id);
    expect(loaded, isNotNull);
    expect(loaded!.session, saved);
    expect(loaded.segments, savedSegments);
  });

  test('loads segments in order', () async {
    await repository.saveSession(session(), [
      StoredSegment(
        sessionId: 'session-1',
        order: 2,
        text: 'third',
      ),
      StoredSegment(
        sessionId: 'session-1',
        order: 0,
        text: 'first',
      ),
      StoredSegment(
        sessionId: 'session-1',
        order: 1,
        text: 'second',
      ),
    ]);

    final loaded = await repository.loadSession('session-1');
    expect(loaded!.segments.map((s) => s.text), ['first', 'second', 'third']);
  });

  test('returns null when loading an unknown session id', () async {
    expect(await repository.loadSession('missing'), isNull);
  });

  test('rejects segments that belong to a different session', () async {
    await expectLater(
      repository.saveSession(session(), segments('other-session')),
      throwsArgumentError,
    );
    expect(await repository.loadSession('session-1'), isNull);
  });

  test('replaceTranscript swaps the segments, marks the session final, and '
      'records the pass usage', () async {
    await repository.saveSession(session(), segments('session-1'));

    final labelled = [
      StoredSegment(
        sessionId: 'session-1',
        order: 0,
        text: 'Hello world',
        speakerLabel: 'speaker_1',
        startSeconds: 0,
        endSeconds: 2.5,
      ),
    ];
    await repository.replaceTranscript(
      'session-1',
      labelled,
      billedAudioSeconds: 126,
      actualCost: 0.0456,
    );

    final loaded = await repository.loadSession('session-1');
    expect(loaded, isNotNull);
    expect(loaded!.session, session(status: SessionStatus.finalized, billedAudioSeconds: 126, actualCost: 0.0456));
    expect(loaded.segments, labelled);
  });

  test('replaceTranscript throws for an unknown session id', () async {
    await expectLater(
      repository.replaceTranscript(
        'missing',
        segments('missing'),
        billedAudioSeconds: 65,
        actualCost: 0.02,
      ),
      throwsArgumentError,
    );
  });

  test('deleteSession removes the session, its segments, and the audio file',
      () async {
    final dir = await Directory.systemTemp.createTemp('voxtral_storage_test_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final audioFile = File('${dir.path}/session-1.wav');
    await audioFile.writeAsBytes([1, 2, 3]);

    await repository.saveSession(
      session(audioPath: audioFile.path),
      segments('session-1'),
    );
    await repository.saveSession(session(id: 'session-2'), segments('session-2'));

    await repository.deleteSession('session-1');

    expect(await repository.loadSession('session-1'), isNull);
    expect(await audioFile.exists(), isFalse);
    // The other session is untouched.
    expect(await repository.loadSession('session-2'), isNotNull);
  });

  test('deleteSession tolerates a missing audio file', () async {
    final audioPath =
        '${(await Directory.systemTemp.createTemp('voxtral_storage_test_')).path}'
        '/gone.wav';
    addTearDown(() async {
      final dir = File(audioPath).parent;
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    await repository.saveSession(
      session(audioPath: audioPath),
      segments('session-1'),
    );

    await repository.deleteSession('session-1');

    expect(await repository.loadSession('session-1'), isNull);
  });

  test('deleteSession is a no-op for an unknown id', () async {
    await repository.deleteSession('missing');
    expect(await repository.loadSession('missing'), isNull);
  });
}
