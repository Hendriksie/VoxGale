// Shared test doubles for the app widget tests (task 5.x): an in-memory
// [ApiKeyStore] and a [FakeLiveSessionController] — a LiveSessionController
// test double with a settable state whose actions record their calls instead
// of touching the capture service, the repository, or the Mistral API. The
// widget tests never hit real services.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:voxtral_live/main.dart';
import 'package:voxtral_live/mistral/mistral.dart';
import 'package:voxtral_live/session/file_transcription_controller.dart';
import 'package:voxtral_live/session/history_detail_controller.dart';
import 'package:voxtral_live/session/live_session_controller.dart';
import 'package:voxtral_live/session/session_providers.dart';
import 'package:voxtral_live/storage/storage.dart';

/// In-memory [ApiKeyStore] for widget tests.
class FakeApiKeyStore implements ApiKeyStore {
  String? key;

  @override
  Future<String?> readKey() async => key;

  @override
  Future<void> saveKey(String newKey) async {
    key = newKey;
  }

  @override
  Future<void> deleteKey() async {
    key = null;
  }
}

/// A [LiveSessionController] test double: [build] returns the fixed, settable
/// state (no capture service, repository, or clock is touched), and the
/// action methods record their calls in [calls].
class FakeLiveSessionController extends LiveSessionController {
  FakeLiveSessionController([LiveSessionState? initial])
      : _state = initial ?? const LiveSessionState();

  final LiveSessionState _state;

  /// The action calls, in order ('start', 'pause', 'resume', 'stop',
  /// 'runDiarizationPass', 'skipDiarizationPass', 'openBatterySettings').
  final List<String> calls = [];

  @override
  LiveSessionState build() => _state;

  /// Replaces the rendered state (a test drives the screen through phases).
  void setState(LiveSessionState value) {
    state = value;
  }

  @override
  Future<void> start({String? language, bool diarize = false}) async {
    calls.add('start');
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
  }

  @override
  Future<void> resume() async {
    calls.add('resume');
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
  }

  @override
  Future<void> runDiarizationPass() async {
    calls.add('runDiarizationPass');
  }

  @override
  Future<void> skipDiarizationPass() async {
    calls.add('skipDiarizationPass');
  }

  @override
  Future<void> openBatterySettings() async {
    calls.add('openBatterySettings');
  }
}

/// A [FileTranscriptionController] test double: [build] returns the fixed,
/// settable state (no picker, prober, repository, or Mistral client is
/// touched), and the action methods record their calls in [calls].
class FakeFileTranscriptionController extends FileTranscriptionController {
  FakeFileTranscriptionController([FileTranscriptionState? initial])
      : _state = initial ?? const FileTranscriptionState();

  final FileTranscriptionState _state;

  /// The action calls, in order: 'pick', 'setModel' with the model id, and
  /// 'transcribe'.
  final List<String> calls = [];

  @override
  FileTranscriptionState build() => _state;

  /// Replaces the rendered state (a test drives the screen through phases).
  void setState(FileTranscriptionState value) {
    state = value;
  }

  @override
  Future<void> pick() async {
    calls.add('pick');
  }

  @override
  void setModel(String model) {
    calls.add('setModel:$model');
  }

  @override
  Future<void> transcribe() async {
    calls.add('transcribe');
  }
}

/// In-memory [SessionRepository] for widget tests (design P2-D3/D6): keeps
/// the records in a map; list is newest-first and search matches segment
/// text. Audio files are not touched (the re-offer's file-existence check
/// uses real temp files in the tests that need them).
class InMemorySessionRepository implements SessionRepository {
  final Map<String, StoredSessionRecord> records = {};

  /// Saves a session with its segments (test helper).
  void add(StoredSession session, List<StoredSegment> segments) {
    records[session.id] = StoredSessionRecord(session: session, segments: segments);
  }

  @override
  Future<void> saveSession(
    StoredSession session,
    List<StoredSegment> segments,
  ) async {
    add(session, segments);
  }

  @override
  Future<StoredSessionRecord?> loadSession(String id) async => records[id];

  @override
  Future<void> replaceTranscript(
    String sessionId,
    List<StoredSegment> segments, {
    required int billedAudioSeconds,
    required double actualCost,
  }) async {
    final record = records[sessionId];
    if (record == null) {
      throw ArgumentError.value(sessionId, 'sessionId', 'Unknown session id');
    }
    final session = record.session;
    records[sessionId] = StoredSessionRecord(
      session: StoredSession(
        id: session.id,
        startedAt: session.startedAt,
        durationSeconds: session.durationSeconds,
        model: session.model,
        status: SessionStatus.finalized,
        billedAudioSeconds: billedAudioSeconds,
        actualCost: actualCost,
        language: session.language,
        audioPath: session.audioPath,
        source: session.source,
        sourceFileName: session.sourceFileName,
      ),
      segments: segments,
    );
  }

  @override
  Future<void> deleteSession(String id) async {
    records.remove(id);
  }

  @override
  Future<List<StoredSession>> listSessions({String? searchQuery}) async {
    final query = searchQuery?.trim() ?? '';
    final sessions = records.values.map((r) => r.session).toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    if (query.isEmpty) {
      return sessions;
    }
    return sessions
        .where((s) => records[s.id]!
            .segments.any((segment) => segment.text.contains(query)))
        .toList();
  }

  @override
  Future<void> deleteAllSessions() async {
    records.clear();
  }

  @override
  Future<void> close() async {}
}

/// A [HistoryDetailController] test double: [build] returns the fixed,
/// settable state (no repository, pass, or file IO is touched), and the
/// action methods record their calls in [calls].
class FakeHistoryDetailController extends HistoryDetailController {
  FakeHistoryDetailController(super.sessionId, [HistoryDetailState? initial])
      : _state = initial ?? const HistoryDetailState();

  final HistoryDetailState _state;

  /// The action calls, in order ('runPass', 'delete').
  final List<String> calls = [];

  @override
  HistoryDetailState build() => _state;

  /// Replaces the rendered state (a test drives the screen through states).
  void setState(HistoryDetailState value) {
    state = value;
  }

  @override
  Future<void> runPass() async {
    calls.add('runPass');
  }

  @override
  Future<void> delete() async {
    calls.add('delete');
  }
}

/// In-memory [PreferencesRepository] for tests (design P2-D3).
class InMemoryPreferencesRepository implements PreferencesRepository {
  StoredPreferences stored = const StoredPreferences();

  @override
  Future<StoredPreferences> loadPreferences() async => stored;

  @override
  Future<void> savePreferences(StoredPreferences preferences) async {
    stored = preferences;
  }
}

/// Pumps the app shell with the given key store, session controller, and
/// theme mode.
ProviderScope appWithStore(
  ApiKeyStore store, {
  ThemeMode? themeMode,
  FakeLiveSessionController? sessionController,
}) =>
    ProviderScope(
      overrides: [
        apiKeyStoreProvider.overrideWith((ref) => store),
        if (sessionController != null)
          liveSessionControllerProvider.overrideWith(() => sessionController),
      ],
      child: VoxtralLiveApp(themeMode: themeMode),
    );
