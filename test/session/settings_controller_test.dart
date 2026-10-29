import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:voxgale/mistral/mistral.dart';
import 'package:voxgale/session/session_providers.dart';
import 'package:voxgale/session/settings_controller.dart';
import 'package:voxgale/storage/storage.dart';

class MockKeyValidationClient extends Mock implements KeyValidationClient {}

class MockAgentClient extends Mock implements AgentClient {}

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
  late MockAgentClient agentClient;
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
    agentClient = MockAgentClient();
    apiKeyStore = FakeApiKeyStore();
    preferences = InMemoryPreferencesRepository();
    container = ProviderContainer(
      overrides: [
        apiKeyStoreProvider.overrideWith((ref) => apiKeyStore),
        keyValidationClientProvider.overrideWith((ref) => validator),
        preferencesRepositoryProvider.overrideWith((ref) => preferences),
        agentClientProvider.overrideWith((ref) async => agentClient),
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
        keepScreenOn: true,
      );

      controller();
      await waitFor(() => state().loaded);

      expect(state().defaultBatchModel, 'voxtral-small-transcribe-3-0');
      expect(state().languageHint, 'de');
      expect(state().keepScreenOn, isTrue);
    });

    test('keep screen on defaults to off when nothing is stored', () async {
      controller();
      await waitFor(() => state().loaded);

      expect(state().keepScreenOn, isFalse);
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

    test('toggling keep screen on persists it and invalidates the '
        'cached preferences provider', () async {
      controller();
      await waitFor(() => state().loaded);
      // Read the provider so its result is cached (Riverpod caches
      // FutureProviders forever — project gotcha).
      expect(
        (await container.read(preferencesProvider.future)).keepScreenOn,
        isFalse,
      );

      await controller().setKeepScreenOn(true);

      expect(state().keepScreenOn, isTrue);
      expect(preferences.stored.keepScreenOn, isTrue);
      // Would be stale without the invalidation in _persistPreferences.
      expect(
        (await container.read(preferencesProvider.future)).keepScreenOn,
        isTrue,
      );

      await controller().setKeepScreenOn(false);

      expect(state().keepScreenOn, isFalse);
      expect(preferences.stored.keepScreenOn, isFalse);
      expect(
        (await container.read(preferencesProvider.future)).keepScreenOn,
        isFalse,
      );
    });
  });

  group('agent picker (change 2026-10-29-send-transcript-to-agent, settings '
      'spec delta)', () {
    const agents = [
      AgentInfo(id: 'ag_1', name: 'Summarizer', description: 'Summarizes'),
      AgentInfo(id: 'ag_2', name: 'Note filer'),
    ];

    test('the initial load applies the stored agent id', () async {
      preferences.stored = const StoredPreferences(agentId: 'ag_2');
      controller();
      await waitFor(() => state().loaded);

      expect(state().selectedAgentId, 'ag_2');
    });

    test('loadAgents fetches the workspace agents into the state', () async {
      apiKeyStore.key = 'sk-secret';
      when(() => agentClient.listAgents()).thenAnswer((_) async => agents);
      controller();
      await waitFor(() => state().loaded);

      await controller().loadAgents();

      expect(state().agents, agents);
      expect(state().agentLoading, isFalse);
      expect(state().hasAgentError, isFalse);
      verify(() => agentClient.listAgents()).called(1);
    });

    test('a failed list load sets the error and keeps the previous '
        'selection', () async {
      apiKeyStore.key = 'sk-secret';
      preferences.stored = const StoredPreferences(agentId: 'ag_1');
      when(() => agentClient.listAgents())
          .thenThrow(MistralApiException('Could not reach the agents API'));
      controller();
      await waitFor(() => state().loaded);

      await controller().loadAgents();

      expect(state().hasAgentError, isTrue);
      expect(state().agentError, 'Could not reach the agents API');
      expect(state().agentLoading, isFalse);
      expect(state().selectedAgentId, 'ag_1');
      expect(state().agents, isEmpty);
    });

    test('selectAgent persists the choice and invalidates the cached '
        'agent-id provider', () async {
      apiKeyStore.key = 'sk-secret';
      controller();
      await waitFor(() => state().loaded);
      // Cache the provider (Riverpod caches FutureProviders forever).
      expect(await container.read(agentIdProvider.future), isNull);

      await controller().selectAgent('ag_1');

      expect(state().selectedAgentId, 'ag_1');
      expect(preferences.stored.agentId, 'ag_1');
      // Would be stale without the invalidation in _persistPreferences.
      expect(await container.read(agentIdProvider.future), 'ag_1');

      await controller().selectAgent(null);

      expect(state().selectedAgentId, isNull);
      expect(preferences.stored.agentId, isNull);
      expect(await container.read(agentIdProvider.future), isNull);
    });
  });
}
