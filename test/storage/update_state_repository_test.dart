import 'package:flutter_test/flutter_test.dart';
import 'package:voxgale/storage/storage.dart';

void main() {
  late AppDatabase db;
  late DriftUpdateStateRepository repository;

  setUp(() {
    db = AppDatabase.memory();
    repository = DriftUpdateStateRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('loads empty update state when nothing is stored', () async {
    final loaded = await repository.loadUpdateState();
    expect(loaded, const StoredUpdateState());
    expect(loaded.lastCheckAtMs, isNull);
    expect(loaded.lastNotifiedVersion, isNull);
  });

  test('round-trips the last-check time and the last-notified version',
      () async {
    const saved = StoredUpdateState(
      lastCheckAtMs: 1761753600000,
      lastNotifiedVersion: '1.3.0',
    );

    await repository.saveUpdateState(saved);

    expect(await repository.loadUpdateState(), saved);
  });

  test('saving replaces the stored row', () async {
    await repository.saveUpdateState(const StoredUpdateState(
      lastCheckAtMs: 1761753600000,
      lastNotifiedVersion: '1.3.0',
    ));

    await repository.saveUpdateState(const StoredUpdateState(
      lastCheckAtMs: 1761840000000,
      lastNotifiedVersion: null,
    ));

    expect(
      await repository.loadUpdateState(),
      const StoredUpdateState(
        lastCheckAtMs: 1761840000000,
        lastNotifiedVersion: null,
      ),
    );
  });

  test('clearing a field persists the null', () async {
    await repository.saveUpdateState(const StoredUpdateState(
      lastCheckAtMs: 1761753600000,
      lastNotifiedVersion: '1.3.0',
    ));

    await repository.saveUpdateState(const StoredUpdateState());

    expect(await repository.loadUpdateState(), const StoredUpdateState());
  });
}
