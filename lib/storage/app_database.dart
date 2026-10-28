// The on-device Drift database holding finalized transcription sessions.
//
// Design P1-D4: two tables — `sessions` (one row per finalized live session)
// and `segments` (the session's transcript, one row per speaker segment) —
// behind the SessionRepository interface so the UI layer stays
// storage-agnostic and mockable. The generated code lives in
// app_database.g.dart (committed; regenerate with
// `dart run build_runner build --delete-conflicting-outputs`).

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

/// One finalized live session (design P1-D4).
class Sessions extends Table {
  /// Stable session id; also the file name of the session audio
  /// (`<id>.wav` in the app's documents directory).
  TextColumn get id => text()();

  /// When the session started (wall clock).
  DateTimeColumn get startedAt => dateTime()();

  /// Session duration in seconds.
  IntColumn get durationSeconds => integer()();

  /// Audio seconds billed by the API (realtime session + post-session
  /// diarization pass), when reported.
  IntColumn get billedAudioSeconds => integer().nullable()();

  /// Actual cost in USD, when known.
  RealColumn get actualCost => real().nullable()();

  /// Realtime model id used for the session.
  TextColumn get model => text()();

  /// Detected or pinned language, when known.
  TextColumn get language => text().nullable()();

  /// `provisional` until the post-session diarization pass replaces the
  /// transcript, `final` afterwards.
  TextColumn get status => text()();

  /// Absolute path of the session audio WAV in app-private storage, or null
  /// once the audio was deleted.
  TextColumn get audioPath => text().nullable()();

  /// Where the transcript came from (design P2-D3): `live` for a live
  /// session, `file` for an imported file transcription.
  TextColumn get source => text().withDefault(const Constant('live'))();

  /// The imported file's name, for `file` sessions; null for live sessions.
  TextColumn get sourceFileName => text().nullable()();
}

/// One transcript segment of a session (design P1-D4).
class Segments extends Table {
  /// The session this segment belongs to; deleted together with the session.
  TextColumn get sessionId =>
      text().references(Sessions, #id, onDelete: KeyAction.cascade)();

  /// Speaker label (`speaker_1`, ...), or null when the transcript was
  /// produced without diarization.
  TextColumn get speakerLabel => text().nullable()();

  /// The segment text. The Dart getter is `segmentText` because a getter
  /// named `text` would clash with drift's `Table.text()` builder; the SQL
  /// column is still `text`.
  TextColumn get segmentText => text().named('text')();

  /// Start time in seconds within the session audio, when known.
  RealColumn get startSeconds => real().nullable()();

  /// End time in seconds within the session audio, when known.
  RealColumn get endSeconds => real().nullable()();

  /// Position of the segment within the session transcript.
  IntColumn get order => integer()();

  @override
  Set<Column> get primaryKey => {sessionId, order};
}

/// The user's persisted transcription preferences (design P2-D3): a single
/// row (id `default`) holding the default batch model and the language
/// hint. Null columns mean "unset" — the readers apply the defaults.
class Preferences extends Table {
  /// Always `default` — the table holds exactly one row.
  TextColumn get id => text()();

  /// Default batch model id (Mini or Small Transcribe 3), or null for the
  /// pinned Mini default.
  TextColumn get defaultBatchModel => text().nullable()();

  /// ISO 639-1 language hint, or null for automatic detection.
  TextColumn get languageHint => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// The app's SQLite database.
@DriftDatabase(tables: [Sessions, Segments, Preferences])
class AppDatabase extends _$AppDatabase {
  /// Opens (creating if needed) the database file in the app's documents
  /// directory, via drift_flutter's platform glue.
  AppDatabase() : super(driftDatabase(name: 'voxgale'));

  /// Creates an in-memory database that persists nothing — for tests.
  AppDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (migrator, from, to) async {
          if (from < 2) {
            // Phase 2 (design P2-D3): sessions learn their source; the
            // preferences table is new. Existing rows default to `live`.
            await migrator.addColumn(sessions, sessions.source);
            await migrator.addColumn(sessions, sessions.sourceFileName);
            await migrator.createTable(preferences);
          }
        },
      );
}
