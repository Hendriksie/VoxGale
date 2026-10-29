// Persistence for the user's transcription preferences (design P2-D3): the
// default batch model, the language hint, and the keep-screen-on toggle,
// stored in the Drift database's single-row `preferences` table. Behind an
// interface so the UI layer stays storage-agnostic and mockable. Null
// columns mean "unset" — the readers apply the defaults (the pinned batch
// Mini model, automatic detection, screen wake lock off).

import 'package:drift/drift.dart';

import 'app_database.dart';

/// The user's persisted transcription preferences (design P2-D3).
class StoredPreferences {
  const StoredPreferences({
    this.defaultBatchModel,
    this.languageHint,
    this.keepScreenOn = false,
  });

  /// Default batch model id (Mini or Small Transcribe 3), or null for the
  /// pinned Mini default.
  final String? defaultBatchModel;

  /// ISO 639-1 language hint, or null for automatic detection.
  final String? languageHint;

  /// Whether the display stays on during live sessions (change
  /// 2026-10-29-keep-screen-on-during-sessions); the stored null reads as
  /// false (off).
  final bool keepScreenOn;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StoredPreferences &&
          defaultBatchModel == other.defaultBatchModel &&
          languageHint == other.languageHint &&
          keepScreenOn == other.keepScreenOn;

  @override
  int get hashCode => Object.hash(defaultBatchModel, languageHint, keepScreenOn);
}

/// Persistence for the user's transcription preferences (design P2-D3).
abstract interface class PreferencesRepository {
  /// Loads the stored preferences; unset fields are null.
  Future<StoredPreferences> loadPreferences();

  /// Saves the preferences, replacing the stored row.
  Future<void> savePreferences(StoredPreferences preferences);
}

/// [PreferencesRepository] backed by the Drift [AppDatabase].
class DriftPreferencesRepository implements PreferencesRepository {
  DriftPreferencesRepository(this._db);

  final AppDatabase _db;

  /// The single row's id.
  static const String rowId = 'default';

  @override
  Future<StoredPreferences> loadPreferences() async {
    final row = await (_db.select(_db.preferences)
          ..where((p) => p.id.equals(rowId)))
        .getSingleOrNull();
    return StoredPreferences(
      defaultBatchModel: row?.defaultBatchModel,
      languageHint: row?.languageHint,
      keepScreenOn: row?.keepScreenOn ?? false,
    );
  }

  @override
  Future<void> savePreferences(StoredPreferences preferences) async {
    await _db.into(_db.preferences).insertOnConflictUpdate(
          PreferencesCompanion.insert(
            id: rowId,
            defaultBatchModel: Value(preferences.defaultBatchModel),
            languageHint: Value(preferences.languageHint),
            keepScreenOn: Value(preferences.keepScreenOn),
          ),
        );
  }
}
