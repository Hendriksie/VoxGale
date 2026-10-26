import 'package:flutter_test/flutter_test.dart';
import 'package:voxtral_live/storage/storage.dart';

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
}
