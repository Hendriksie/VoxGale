// Riverpod wiring for the live session (design P1-D7, tasks 4.1-4.4): the
// pinned Mistral config, the API key store, the session repository, the
// capture service, the post-session diarization pass, and the live session
// controller. The config/key providers moved here from lib/spike/ (the spike
// harness re-exports them). The API key is read only at client construction
// (exactly like the spike harness) and injected only into the lib/mistral/
// clients — it never reaches the controller or its state.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mistral/mistral.dart';
import '../storage/storage.dart';
import 'capture_service.dart';
import 'diarization_pass.dart';
import 'file_transcription_controller.dart';
import 'live_session_controller.dart';
import 'settings_controller.dart';

/// Pinned model IDs and rates (single source, design D3/D7).
final mistralConfigProvider =
    Provider<MistralConfig>((ref) => MistralConfig.defaults);

/// Secure-storage-backed API key store.
final apiKeyStoreProvider =
    Provider<ApiKeyStore>((ref) => SecureStorageApiKeyStore());

/// The user's saved API key, or null when none is saved.
final apiKeyProvider =
    FutureProvider<String?>((ref) => ref.watch(apiKeyStoreProvider).readKey());

/// The app's SQLite database, shared by the storage repositories (design
/// P2-D3). Closed when the provider is disposed.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// The on-device store for finalized sessions.
final sessionRepositoryProvider = Provider<SessionRepository>(
    (ref) => DriftSessionRepository(ref.watch(appDatabaseProvider)));

/// The store for the user's transcription preferences (design P2-D3).
final preferencesRepositoryProvider = Provider<PreferencesRepository>(
    (ref) => DriftPreferencesRepository(ref.watch(appDatabaseProvider)));

/// The user's persisted preferences; unset fields are null.
final preferencesProvider = FutureProvider<StoredPreferences>(
    (ref) => ref.watch(preferencesRepositoryProvider).loadPreferences());

/// The default batch model for transcriptions that don't choose one: the
/// persisted preference, falling back to the pinned Mini model (settings
/// spec).
final defaultBatchModelProvider = FutureProvider<String>((ref) async {
  final config = ref.watch(mistralConfigProvider);
  final preferences = await ref.watch(preferencesProvider.future);
  return preferences.defaultBatchModel ?? config.batchMiniModel;
});

/// The pinned language hint, or null for automatic detection (settings spec).
final languageHintProvider = FutureProvider<String?>((ref) async {
  final preferences = await ref.watch(preferencesProvider.future);
  return preferences.languageHint;
});

/// Validates a candidate API key with a cheap test request before it is
/// treated as saved (settings spec). The candidate key is passed per call,
/// so the settings controller can validate before saving.
final keyValidationClientProvider =
    Provider<KeyValidationClient>((ref) => DioKeyValidationClient());

/// The batch client the post-session diarization pass runs on. The API key
/// is read here — at client construction, exactly like the spike harness —
/// and injected only into the lib/mistral/ client.
final batchTranscriptionClientProvider =
    FutureProvider<BatchTranscriptionClient>((ref) async {
  final key = await ref.watch(apiKeyStoreProvider).readKey();
  if (key == null || key.isEmpty) {
    throw StateError('No API key saved');
  }
  return DioBatchTranscriptionClient(apiKey: key);
});

/// The post-session diarization pass (design P1-D5).
final diarizationPassProvider = FutureProvider<DiarizationPass>((ref) async {
  final client = await ref.watch(batchTranscriptionClientProvider.future);
  return DiarizationPass(
    client: client,
    repository: ref.watch(sessionRepositoryProvider),
    config: ref.watch(mistralConfigProvider),
  );
});

/// The capture service (UI-side wrapper around the foreground service).
final captureServiceProvider =
    Provider<CaptureService>((ref) => CaptureService());

/// The clock driving the elapsed-time display.
final sessionClockProvider =
    Provider<SessionClock>((ref) => const SystemSessionClock());

/// How long [LiveSessionController.stop] waits for the service's final
/// session-ended event before failing the session.
final sessionFinalizeTimeoutProvider =
    Provider<Duration>((ref) => const Duration(seconds: 5));

/// The live session controller.
final liveSessionControllerProvider =
    NotifierProvider<LiveSessionController, LiveSessionState>(
        LiveSessionController.new);

/// The settings screen's controller (design P2-D4).
final settingsControllerProvider =
    NotifierProvider<SettingsController, SettingsState>(
        SettingsController.new);

/// The system file picker seam for audio files (design P2-D1).
final audioFilePickerProvider =
    Provider<AudioFilePicker>((ref) => FilePickerAudioFilePicker());

/// The audio-duration prober seam (design P2-D2).
final audioDurationProberProvider =
    Provider<AudioDurationProber>((ref) => JustAudioDurationProber());

/// The file transcription controller (design P2-D1).
final fileTranscriptionControllerProvider =
    NotifierProvider<FileTranscriptionController, FileTranscriptionState>(
        FileTranscriptionController.new);
