// Session persistence behind a storage-agnostic interface (design P1-D4).
//
// The UI layer depends on [SessionRepository] only, so it stays
// storage-agnostic and mockable; [DriftSessionRepository] is the production
// implementation over the Drift [AppDatabase].

import 'dart:io';

import 'package:drift/drift.dart';

import 'app_database.dart';

/// Lifecycle status of a stored session.
enum SessionStatus {
  /// Saved at session end carrying the provisional live transcript; the
  /// post-session diarization pass has not replaced it yet. Stored as
  /// `provisional` in the database.
  provisional,

  /// The speaker-labelled transcript from the post-session diarization pass
  /// is the transcript of record. Stored as `final` in the database (`final`
  /// is a Dart keyword, hence the constant name).
  finalized,
}

/// A finalized session as persisted on device.
class StoredSession {
  const StoredSession({
    required this.id,
    required this.startedAt,
    required this.durationSeconds,
    required this.model,
    required this.status,
    this.billedAudioSeconds,
    this.actualCost,
    this.language,
    this.audioPath,
  });

  /// Stable session id; also the file name of the session audio
  /// (`<id>.wav` in the app's documents directory).
  final String id;

  /// When the session started (wall clock).
  final DateTime startedAt;

  /// Session duration in seconds.
  final int durationSeconds;

  /// Realtime model id used for the session.
  final String model;

  /// Whether the transcript is provisional or final — see [SessionStatus].
  final SessionStatus status;

  /// Audio seconds billed by the API, when reported.
  final int? billedAudioSeconds;

  /// Actual cost in USD, when known.
  final double? actualCost;

  /// Detected or pinned language, when known.
  final String? language;

  /// Absolute path of the session audio WAV in app-private storage, or null
  /// once the audio was deleted.
  final String? audioPath;

  /// Two sessions are equal when they describe the same stored record.
  /// [startedAt] is compared at millisecond precision — the precision the
  /// SQLite column stores — so a save/load round-trip preserves equality
  /// (drift also drops the UTC/local distinction on load).
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StoredSession &&
          id == other.id &&
          startedAt.millisecondsSinceEpoch ==
              other.startedAt.millisecondsSinceEpoch &&
          durationSeconds == other.durationSeconds &&
          billedAudioSeconds == other.billedAudioSeconds &&
          actualCost == other.actualCost &&
          model == other.model &&
          language == other.language &&
          status == other.status &&
          audioPath == other.audioPath;

  @override
  int get hashCode => Object.hash(
        id,
        startedAt.millisecondsSinceEpoch,
        durationSeconds,
        billedAudioSeconds,
        actualCost,
        model,
        language,
        status,
        audioPath,
      );
}

/// One transcript segment of a stored session.
class StoredSegment {
  const StoredSegment({
    required this.sessionId,
    required this.order,
    required this.text,
    this.speakerLabel,
    this.startSeconds,
    this.endSeconds,
  });

  /// The session this segment belongs to.
  final String sessionId;

  /// Position of the segment within the session transcript.
  final int order;

  /// The segment text.
  final String text;

  /// Speaker label (`speaker_1`, ...), or null when the transcript was
  /// produced without diarization.
  final String? speakerLabel;

  /// Start time in seconds within the session audio, when known.
  final double? startSeconds;

  /// End time in seconds within the session audio, when known.
  final double? endSeconds;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StoredSegment &&
          sessionId == other.sessionId &&
          order == other.order &&
          text == other.text &&
          speakerLabel == other.speakerLabel &&
          startSeconds == other.startSeconds &&
          endSeconds == other.endSeconds;

  @override
  int get hashCode =>
      Object.hash(sessionId, order, text, speakerLabel, startSeconds, endSeconds);
}

/// A stored session together with its transcript segments.
class StoredSessionRecord {
  const StoredSessionRecord({required this.session, required this.segments});

  final StoredSession session;

  /// The transcript segments, ordered by [StoredSegment.order].
  final List<StoredSegment> segments;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StoredSessionRecord &&
          session == other.session &&
          segments.length == other.segments.length &&
          _listEquals(segments, other.segments);

  @override
  int get hashCode => Object.hash(session, Object.hashAll(segments));

  static bool _listEquals(List<StoredSegment> a, List<StoredSegment> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Persistence for finalized live sessions (design P1-D4).
///
/// Implementations must make [saveSession] and [replaceTranscript] atomic:
/// a session is never visible with a half-written transcript.
abstract interface class SessionRepository {
  /// Saves a finalized session together with its transcript segments.
  Future<void> saveSession(StoredSession session, List<StoredSegment> segments);

  /// Loads a session and its ordered segments by id, or null when no session
  /// with [id] exists.
  Future<StoredSessionRecord?> loadSession(String id);

  /// Replaces the transcript of a session with the speaker-labelled segments
  /// from the post-session diarization pass, marks the session
  /// [SessionStatus.finalized], and records the pass's billed usage as the
  /// session's totals.
  Future<void> replaceTranscript(
    String sessionId,
    List<StoredSegment> segments, {
    required int billedAudioSeconds,
    required double actualCost,
  });

  /// Deletes a session, its segments, and its audio file (when the file still
  /// exists). Deleting an unknown id is a no-op.
  Future<void> deleteSession(String id);

  /// Closes the underlying storage. The repository cannot be used afterwards.
  Future<void> close();
}

/// [SessionRepository] backed by the Drift [AppDatabase].
class DriftSessionRepository implements SessionRepository {
  DriftSessionRepository(this._db);

  final AppDatabase _db;

  @override
  Future<void> saveSession(
    StoredSession session,
    List<StoredSegment> segments,
  ) async {
    for (final segment in segments) {
      if (segment.sessionId != session.id) {
        throw ArgumentError.value(
          segment.sessionId,
          'segments',
          'Segment belongs to a different session',
        );
      }
    }
    await _db.transaction(() async {
      await _db.into(_db.sessions).insert(_sessionCompanion(session));
      await _db.batch((batch) {
        batch.insertAll(
          _db.segments,
          segments.map(_segmentCompanion).toList(),
        );
      });
    });
  }

  @override
  Future<StoredSessionRecord?> loadSession(String id) async {
    final row = await (_db.select(_db.sessions)
          ..where((s) => s.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      return null;
    }
    final segmentRows = await (_db.select(_db.segments)
          ..where((s) => s.sessionId.equals(id))
          ..orderBy([(s) => OrderingTerm(expression: s.order)]))
        .get();
    return StoredSessionRecord(
      session: _toStoredSession(row),
      segments: segmentRows.map(_toStoredSegment).toList(),
    );
  }

  @override
  Future<void> replaceTranscript(
    String sessionId,
    List<StoredSegment> segments, {
    required int billedAudioSeconds,
    required double actualCost,
  }) async {
    for (final segment in segments) {
      if (segment.sessionId != sessionId) {
        throw ArgumentError.value(
          segment.sessionId,
          'segments',
          'Segment belongs to a different session',
        );
      }
    }
    await _db.transaction(() async {
      final updated = await (_db.update(_db.sessions)
            ..where((s) => s.id.equals(sessionId)))
          .write(
        SessionsCompanion(
          status: Value(_statusToText(SessionStatus.finalized)),
          billedAudioSeconds: Value(billedAudioSeconds),
          actualCost: Value(actualCost),
        ),
      );
      if (updated == 0) {
        throw ArgumentError.value(sessionId, 'sessionId', 'Unknown session id');
      }
      await (_db.delete(_db.segments)
            ..where((s) => s.sessionId.equals(sessionId)))
          .go();
      await _db.batch((batch) {
        batch.insertAll(
          _db.segments,
          segments.map(_segmentCompanion).toList(),
        );
      });
    });
  }

  @override
  Future<void> deleteSession(String id) async {
    final record = await loadSession(id);
    await _db.transaction(() async {
      await (_db.delete(_db.segments)..where((s) => s.sessionId.equals(id)))
          .go();
      await (_db.delete(_db.sessions)..where((s) => s.id.equals(id))).go();
    });
    final audioPath = record?.session.audioPath;
    if (audioPath == null) {
      return;
    }
    final file = File(audioPath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<void> close() => _db.close();

  SessionsCompanion _sessionCompanion(StoredSession session) {
    return SessionsCompanion.insert(
      id: session.id,
      startedAt: session.startedAt,
      durationSeconds: session.durationSeconds,
      billedAudioSeconds: Value(session.billedAudioSeconds),
      actualCost: Value(session.actualCost),
      model: session.model,
      language: Value(session.language),
      status: _statusToText(session.status),
      audioPath: Value(session.audioPath),
    );
  }

  SegmentsCompanion _segmentCompanion(StoredSegment segment) {
    return SegmentsCompanion.insert(
      sessionId: segment.sessionId,
      speakerLabel: Value(segment.speakerLabel),
      segmentText: segment.text,
      startSeconds: Value(segment.startSeconds),
      endSeconds: Value(segment.endSeconds),
      order: segment.order,
    );
  }

  StoredSession _toStoredSession(Session row) {
    return StoredSession(
      id: row.id,
      startedAt: row.startedAt,
      durationSeconds: row.durationSeconds,
      model: row.model,
      status: _statusFromText(row.status),
      billedAudioSeconds: row.billedAudioSeconds,
      actualCost: row.actualCost,
      language: row.language,
      audioPath: row.audioPath,
    );
  }

  StoredSegment _toStoredSegment(Segment row) {
    return StoredSegment(
      sessionId: row.sessionId,
      order: row.order,
      text: row.segmentText,
      speakerLabel: row.speakerLabel,
      startSeconds: row.startSeconds,
      endSeconds: row.endSeconds,
    );
  }

  static String _statusToText(SessionStatus status) {
    return switch (status) {
      SessionStatus.provisional => 'provisional',
      SessionStatus.finalized => 'final',
    };
  }

  static SessionStatus _statusFromText(String text) {
    return switch (text) {
      'final' => SessionStatus.finalized,
      _ => SessionStatus.provisional,
    };
  }
}
