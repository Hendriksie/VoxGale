import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voxgale/storage/storage.dart';

void main() {
  late AppDatabase db;
  late DriftPreferencesRepository repository;

  setUp(() {
    db = AppDatabase.memory();
    repository = DriftPreferencesRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('loads empty preferences when nothing is stored', () async {
    final loaded = await repository.loadPreferences();
    expect(loaded, const StoredPreferences());
    expect(loaded.defaultBatchModel, isNull);
    expect(loaded.languageHint, isNull);
    expect(loaded.keepScreenOn, isFalse);
  });

  test('round-trips the default batch model and the language hint', () async {
    const saved = StoredPreferences(
      defaultBatchModel: 'voxtral-small-transcribe-3-0',
      languageHint: 'de',
    );

    await repository.savePreferences(saved);

    expect(await repository.loadPreferences(), saved);
  });

  test('saving replaces the stored row', () async {
    await repository.savePreferences(const StoredPreferences(
      defaultBatchModel: 'voxtral-small-transcribe-3-0',
      languageHint: 'de',
    ));

    await repository.savePreferences(const StoredPreferences(
      defaultBatchModel: 'voxtral-mini-transcribe-3-0',
      languageHint: null,
    ));

    expect(
      await repository.loadPreferences(),
      const StoredPreferences(
        defaultBatchModel: 'voxtral-mini-transcribe-3-0',
        languageHint: null,
      ),
    );
  });

  test('clearing a field persists the null', () async {
    await repository.savePreferences(const StoredPreferences(
      defaultBatchModel: 'voxtral-small-transcribe-3-0',
      languageHint: 'de',
    ));

    await repository.savePreferences(const StoredPreferences());

    expect(await repository.loadPreferences(), const StoredPreferences());
  });

  test('keep screen on round-trips and clearing it persists off', () async {
    await repository.savePreferences(
      const StoredPreferences(keepScreenOn: true),
    );

    final loaded = await repository.loadPreferences();
    expect(loaded.keepScreenOn, isTrue);
    expect(loaded, const StoredPreferences(keepScreenOn: true));

    await repository.savePreferences(const StoredPreferences());

    expect((await repository.loadPreferences()).keepScreenOn, isFalse);
  });

  // Plain test() with real file IO — testWidgets + dart:io deadlocks
  // (project gotcha). A file-backed database proves the preference survives
  // a close and reopen (an in-memory database cannot).
  test('keep screen on persists across a close and reopen', () async {
    final dir = await Directory.systemTemp.createTemp('voxgale_preferences');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/preferences.sqlite');
    const saved = StoredPreferences(keepScreenOn: true);

    final first = AppDatabase.file(file);
    await DriftPreferencesRepository(first).savePreferences(saved);
    await first.close();

    final second = AppDatabase.file(file);
    addTearDown(second.close);
    expect(await DriftPreferencesRepository(second).loadPreferences(), saved);
  });
}
