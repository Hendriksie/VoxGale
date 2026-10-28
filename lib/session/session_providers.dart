// Riverpod wiring for the live session (design P1-D7, tasks 4.1-4.4): the
// pinned Mistral config, the API key store, the session repository, the
// capture service, the post-session diarization pass, and the live session
// controller. The config/key providers moved here from the Phase-0 spike
// harness (removed in Phase 4). The API key is read only at client
// construction and injected only into the lib/mistral/ clients — it never
// reaches the controller or its state.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mistral/mistral.dart';
import '../storage/storage.dart';
import 'audio_focus_gateway.dart';
import 'capture_service.dart';
import 'diarization_pass.dart';
import 'file_transcription_controller.dart';
import 'history_detail_controller.dart';
import 'history_search_query.dart';
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

/// Whether an API key is currently saved. Presence only — the key value
/// never propagates past this provider (the store and the lib/mistral
/// clients are the only readers of the value). The settings controller
/// invalidates [apiKeyProvider] after save/remove, so this re-computes and
/// its watchers (the missing-key states) follow key changes without a
/// restart (empty-error-states spec).
final apiKeyPresentProvider = FutureProvider<bool>((ref) async {
  final key = await ref.watch(apiKeyProvider.future);
  return key != null && key.isNotEmpty;
});

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

/// The post-session diarization pass (design P1-D5, P2-D7): transcribes with
/// the configured default batch model preference (the pinned Mini model
/// unless the user changed it in settings).
final diarizationPassProvider = FutureProvider<DiarizationPass>((ref) async {
  final client = await ref.watch(batchTranscriptionClientProvider.future);
  final model = await ref.watch(defaultBatchModelProvider.future);
  return DiarizationPass(
    client: client,
    repository: ref.watch(sessionRepositoryProvider),
    config: ref.watch(mistralConfigProvider),
    model: model,
  );
});

/// The capture service (UI-side wrapper around the foreground service).
final captureServiceProvider =
    Provider<CaptureService>((ref) => CaptureService());

/// The foreground-task gateway behind the capture service — the platform
/// seam for the runtime-permission requests. The live screen's
/// mic-permission-denied remedy re-requests RECORD_AUDIO through it
/// (Phase 3 group 2); the gateway prompts natively via the `record` package.
final foregroundTaskGatewayProvider =
    Provider<ForegroundTaskGateway>((ref) => PluginForegroundTaskGateway());

/// The audio-focus gateway behind the live session controller (design
/// P3-D2, task 3.1): the platform seam for audio-focus management. The
/// controller configures the audio session for recording when a capture
/// session becomes active, pauses capture when another app takes audio
/// focus (e.g. an incoming phone call), and resumes when focus returns
/// (live-transcription spec "Respect audio focus").
final audioFocusGatewayProvider =
    Provider<AudioFocusGateway>((ref) => AudioSessionFocusGateway());

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

/// The history screen's search query (transcript-history spec: search by
/// text content). AutoDispose: the query resets when the history screen is
/// popped, so a reopened screen always starts from an empty search bar.
final historySearchQueryProvider =
    NotifierProvider.autoDispose<HistorySearchQuery, String>(
        HistorySearchQuery.new);

/// The saved sessions for the history list, newest first, filtered by the
/// search query (transcript-history spec). AutoDispose: reopening the
/// history screen re-runs the query, so newly saved transcripts show up.
/// The mutation sites (session saves, transcript replacements) also
/// invalidate this provider while the screen is mounted.
final historyListProvider = FutureProvider.autoDispose<List<StoredSession>>(
    (ref) async {
  final query = ref.watch(historySearchQueryProvider);
  return ref
      .read(sessionRepositoryProvider)
      .listSessions(searchQuery: query.isEmpty ? null : query);
});

/// The history detail controller for one session (design P2-D6/D7), keyed by
/// session id; auto-disposed when its screen is popped.
final historyDetailControllerProvider = NotifierProvider.autoDispose.family<
    HistoryDetailController, HistoryDetailState, String>(
  HistoryDetailController.new,
);
