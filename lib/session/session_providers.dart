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
import 'live_session_controller.dart';

/// Pinned model IDs and rates (single source, design D3/D7).
final mistralConfigProvider =
    Provider<MistralConfig>((ref) => MistralConfig.defaults);

/// Secure-storage-backed API key store.
final apiKeyStoreProvider =
    Provider<ApiKeyStore>((ref) => SecureStorageApiKeyStore());

/// The user's saved API key, or null when none is saved.
final apiKeyProvider =
    FutureProvider<String?>((ref) => ref.watch(apiKeyStoreProvider).readKey());

/// The on-device store for finalized sessions.
final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  final repository = DriftSessionRepository(AppDatabase());
  ref.onDispose(repository.close);
  return repository;
});

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
