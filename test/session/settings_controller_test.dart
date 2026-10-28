import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:voxgale/mistral/mistral.dart';
import 'package:voxgale/session/session_providers.dart';
import 'package:voxgale/session/settings_controller.dart';
import 'package:voxgale/storage/storage.dart';

class MockKeyValidationClient extends Mock implements KeyValidationClient {}

class FakeApiKeyStore implements ApiKeyStore {
  String? key;

  @override
  Future<String?> readKey() async => key;

  @override
  Future<void> saveKey(String newKey) async => key = newKey;

  @override
  Future<void> deleteKey() async => key = null;
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
  late MockKeyValidationClient validator;
  late FakeApiKeyStore apiKeyStore;
  late InMemoryPreferencesRepository preferences;
  late ProviderContainer container;

  SettingsState state() => container.read(settingsControllerProvider);

  SettingsController controller() =>
      container.read(settingsControllerProvider.notifier);

  /// Lets the event loop run until [condition] holds (with a timeout).
  Future<void> waitFor(bool Function() condition) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(condition(), isTrue);
  }

  setUp(() {
    validator = MockKeyValidationClient();
    apiKeyStore = FakeApiKeyStore();
    preferences = InMemoryPreferencesRepository();
    container = ProviderContainer(
      overrides: [
        apiKeyStoreProvider.overrideWith((ref) => apiKeyStore),
        keyValidationClientProvider.overrideWith((ref) => validator),
        preferencesRepositoryProvider.overrideWith((ref) => preferences),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('initial load', () {
    test('reports the key status without ever carrying the key value',
        () async {
      apiKeyStore.key = 'sk-secret';
      // Build the controller so its async load runs.
      controller();
      await waitFor(() => state().loaded);

      expect(state().keySaved, isTrue);
      expect(state().toString(), isNot(contains('sk-secret')));
    });

    test('shows a missing-key state when no key is saved', () async {
      controller();
      await waitFor(() => state().loaded);

      expect(state().keySaved, isFalse);
    });

    test('loads the stored preferences', () async {
      preferences.stored = const StoredPreferences(
        defaultBatchModel: 'voxtral-small-transcribe-3-0',
        languageHint: 'de',
      );

      controller();
      await waitFor(() => state().loaded);

      expect(state().defaultBatchModel, 'voxtral-small-transcribe-3-0');
      expect(state().languageHint, 'de');
    });
  });

  group('saveKey (settings spec: validate before treating as saved)', () {
    test('a valid key is validated, then saved to secure storage', () async {
      when(() => validator.validate(any())).thenAnswer((_) async {});
      controller();

      await controller().saveKey('  sk-new-key  ');

      verify(() => validator.validate('sk-new-key')).called(1);
      expect(apiKeyStore.key, 'sk-new-key');
      expect(state().keySaved, isTrue);
      expect(state().validating, isFalse);
      expect(state().info, 'API key saved.');
      expect(state().hasError, isFalse);
    });

    test('an invalid key is not saved and shows the validation error',
        () async {
      when(() => validator.validate(any()))
          .thenThrow(MistralApiException('The API key was rejected.'));
      controller();

      await controller().saveKey('sk-bad');

      expect(apiKeyStore.key, isNull);
      expect(state().keySaved, isFalse);
      expect(state().validating, isFalse);
      expect(state().error, 'The API key was rejected.');
    });

    test('a validation failure is retryable: a later valid save succeeds',
        () async {
      var calls = 0;
      when(() => validator.validate(any())).thenAnswer((_) async {
        calls++;
        if (calls == 1) {
          throw MistralApiException('Could not reach the Mistral API.');
        }
      });
      controller();

      await controller().saveKey('sk-flaky');
      expect(state().hasError, isTrue);
      expect(apiKeyStore.key, isNull);

      await controller().saveKey('sk-flaky');
      expect(state().hasError, isFalse);
      expect(apiKeyStore.key, 'sk-flaky');
      expect(state().keySaved, isTrue);
    });

    test('an empty key is a no-op', () async {
      controller();

      await controller().saveKey('   ');

      verifyNever(() => validator.validate(any()));
      expect(apiKeyStore.key, isNull);
    });
  });

  group('removeKey (settings spec)', () {
    test('removes the stored key so no transcription can run until a new '
        'one is saved', () async {
      apiKeyStore.key = 'sk-existing';
      controller();
      await waitFor(() => state().keySaved);

      await controller().removeKey();

      expect(apiKeyStore.key, isNull);
      expect(state().keySaved, isFalse);
      expect(state().info, 'API key removed.');
    });
  });

  group('preferences (settings spec: persisted, applied to new '
      'transcriptions)', () {
    test('changing the default batch model persists it', () async {
      controller();
      await waitFor(() => state().loaded);

      await controller().setDefaultBatchModel('voxtral-small-transcribe-3-0');

      expect(preferences.stored.defaultBatchModel,
          'voxtral-small-transcribe-3-0');
      expect(state().defaultBatchModel, 'voxtral-small-transcribe-3-0');
    });

    test('changing the language hint persists it', () async {
      controller();
      await waitFor(() => state().loaded);

      await controller().setLanguageHint('fr');

      expect(preferences.stored.languageHint, 'fr');
      expect(state().languageHint, 'fr');
    });

    test('clearing the language hint persists automatic detection', () async {
      preferences.stored =
          const StoredPreferences(languageHint: 'fr');
      controller();
      await waitFor(() => state().loaded);

      await controller().setLanguageHint(null);

      expect(preferences.stored.languageHint, isNull);
      expect(state().languageHint, isNull);
    });
  });
}
