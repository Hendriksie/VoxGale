// Persistence for the app's update-check state (change
// 2026-10-29-update-tracker, design decision 6): when the last well-formed
// update check ran and which available version was last notified to the
// user, stored in the Drift database's single-row `update_state` table.
// Behind an interface so the update layer stays storage-agnostic and
// mockable. Null fields mean "unset" — no check has succeeded yet, no
// version has been notified yet. The check time is epoch milliseconds
// because a Drift DateTime round-trip loses zone and sub-millisecond
// precision.

import 'package:drift/drift.dart';

import 'app_database.dart';

/// The app's persisted update-check state (change
/// 2026-10-29-update-tracker, design decision 6).
class StoredUpdateState {
  const StoredUpdateState({this.lastCheckAtMs, this.lastNotifiedVersion});

  /// When the last well-formed update check completed, as epoch
  /// milliseconds, or null when no check has succeeded yet.
  final int? lastCheckAtMs;

  /// The available version last notified to the user, or null when no
  /// version has been notified yet.
  final String? lastNotifiedVersion;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StoredUpdateState &&
          lastCheckAtMs == other.lastCheckAtMs &&
          lastNotifiedVersion == other.lastNotifiedVersion;

  @override
  int get hashCode => Object.hash(lastCheckAtMs, lastNotifiedVersion);
}

/// Persistence for the app's update-check state (change
/// 2026-10-29-update-tracker, design decision 6).
abstract interface class UpdateStateRepository {
  /// Loads the stored update-check state; unset fields are null.
  Future<StoredUpdateState> loadUpdateState();

  /// Saves the update-check state, replacing the stored row.
  Future<void> saveUpdateState(StoredUpdateState state);
}

/// [UpdateStateRepository] backed by the Drift [AppDatabase].
class DriftUpdateStateRepository implements UpdateStateRepository {
  DriftUpdateStateRepository(this._db);

  final AppDatabase _db;

  /// The single row's id.
  static const String rowId = 'default';

  @override
  Future<StoredUpdateState> loadUpdateState() async {
    final row = await (_db.select(_db.updateState)
          ..where((u) => u.id.equals(rowId)))
        .getSingleOrNull();
    return StoredUpdateState(
      lastCheckAtMs: row?.lastCheckAtMs,
      lastNotifiedVersion: row?.lastNotifiedVersion,
    );
  }

  @override
  Future<void> saveUpdateState(StoredUpdateState state) async {
    await _db.into(_db.updateState).insertOnConflictUpdate(
          UpdateStateCompanion.insert(
            id: rowId,
            lastCheckAtMs: Value(state.lastCheckAtMs),
            lastNotifiedVersion: Value(state.lastNotifiedVersion),
          ),
        );
  }
}
