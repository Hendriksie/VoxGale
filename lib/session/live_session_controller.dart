// The live session controller (design P1-D2/D5/D7, tasks 4.1-4.4): a Riverpod
// notifier owning the live-session state machine
// idle → starting → active ⇄ paused → stopping → finalizing → pass-offered
// → pass-running → done / pass-failed. It groups the service's event stream
// into turns, drives pause/resume, finalizes the session on the graceful
// stop (persistence + the pass offer), and runs the post-session
// diarization pass. The UI renders [LiveSessionState] directly.
//
// Audio focus (design P3-D2, live-transcription "Respect audio focus"): when
// the session becomes active the controller configures the platform audio
// session for recording through the [AudioFocusGateway] seam; a focus loss
// pauses capture through the same pause path a user pause uses, and the
// focus return resumes — unless the user paused. The state's
// [LiveSessionState.pausedByAudioFocus] flag lets the UI word the pause.
//
// The controller depends only on the Mistral interfaces, [MistralConfig],
// the domain value objects, the [SessionRepository] interface, and the
// [CaptureService] wrapper. The API key itself is never read here — only its
// presence (for the no-key error state); the key is read inside the capture
// service isolate and inside the lib/mistral/ clients only.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mistral/mistral.dart';
import '../storage/storage.dart';
import 'audio_focus_gateway.dart';
import 'capture_service.dart';
import 'diarization_pass.dart';
import 'session_models.dart';
import 'session_providers.dart';

/// The phase of a live session (design P1-D7): the capture lifecycle of
/// [SessionState] extended with the post-session pass states the controller
/// owns.
enum LiveSessionPhase {
  /// No session running.
  idle,

  /// The capture service is starting (key presence, battery check, service).
  starting,

  /// Capturing and transcribing.
  active,

  /// Paused by the user; the realtime session stays open (design P1-D2).
  paused,

  /// Stop requested; the graceful end is in flight.
  stopping,

  /// The service ended; the final transcript is being persisted.
  finalizing,

  /// The session is saved (provisional transcript); the diarization pass is
  /// offered with its estimated cost.
  passOffered,

  /// The diarization pass is running.
  passRunning,

  /// The session is complete: the pass ran (the labelled transcript is the
  /// transcript of record) or was skipped (the provisional transcript is
  /// the transcript of record and the audio is kept).
  done,

  /// The diarization pass failed; the provisional transcript is preserved
  /// and the pass can be retried.
  passFailed,

  /// An unrecoverable error ended the session.
  error,
}

/// Connection-interruption info for the subtle in-UI indicator
/// (live-transcription delta): what happened to the transcription stream,
/// outside the transcript text.
class ConnectionStatus {
  const ConnectionStatus({
    this.reconnectCount = 0,
    this.lastDropReason,
    this.lastReplayedSeconds,
    this.lastDroppedSeconds,
  });

  /// How many times the stream reconnected during the session.
  final int reconnectCount;

  /// Why the previous connection dropped (close code/reason), when known.
  final String? lastDropReason;

  /// How many seconds of buffered audio were replayed after the last
  /// reconnect, when a replay happened.
  final double? lastReplayedSeconds;

  /// How many seconds of buffered audio were dropped (the buffer cap was
  /// reached) at the last reconnect, when audio was lost — the transcript
  /// shows a gap there.
  final double? lastDroppedSeconds;

  /// Whether the stream had any interruption.
  bool get hadInterruption => reconnectCount > 0 || lastDroppedSeconds != null;

  ConnectionStatus copyWith({
    int? reconnectCount,
    String? lastDropReason,
    double? lastReplayedSeconds,
    double? lastDroppedSeconds,
  }) =>
      ConnectionStatus(
        reconnectCount: reconnectCount ?? this.reconnectCount,
        lastDropReason: lastDropReason ?? this.lastDropReason,
        lastReplayedSeconds: lastReplayedSeconds ?? this.lastReplayedSeconds,
        lastDroppedSeconds: lastDroppedSeconds ?? this.lastDroppedSeconds,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConnectionStatus &&
          reconnectCount == other.reconnectCount &&
          lastDropReason == other.lastDropReason &&
          lastReplayedSeconds == other.lastReplayedSeconds &&
          lastDroppedSeconds == other.lastDroppedSeconds;

  @override
  int get hashCode =>
      Object.hash(reconnectCount, lastDropReason, lastReplayedSeconds, lastDroppedSeconds);
}

/// The immutable, UI-ready state of the live session (design P1-D7): a
/// screen renders it directly. Value equality: two states with the same
/// content are equal.
class LiveSessionState {
  const LiveSessionState({
    this.phase = LiveSessionPhase.idle,
    this.turns = const [],
    this.gapMarkers = const [],
    this.elapsedSeconds = 0,
    this.estimatedCost = 0,
    this.sessionId,
    this.durationSeconds = 0,
    this.model,
    this.language,
    this.realtimeBilledSeconds,
    this.realtimeActualCost,
    this.passEstimatedCost,
    this.passBilledSeconds,
    this.passActualCost,
    this.connection = const ConnectionStatus(),
    this.error = '',
    this.missingApiKey = false,
    this.batteryPromptNeeded = false,
    this.pausedByAudioFocus = false,
  });

  /// Where the session is in its lifecycle — see [LiveSessionPhase].
  final LiveSessionPhase phase;

  /// The turn-grouped transcript. Provisional (streaming) until the
  /// post-session diarization pass replaces it with labelled turns.
  final List<TranscriptTurn> turns;

  /// Visible gap markers where buffered audio was dropped (the reconnect
  /// buffer's cap was exceeded), rendered at the position of each drop
  /// (live-transcription spec). Cleared when the pass replaces the
  /// provisional transcript.
  final List<TranscriptGap> gapMarkers;

  /// Elapsed wall-clock seconds since the session started. Keeps counting
  /// while paused (the notification shows the same elapsed time).
  final int elapsedSeconds;

  /// The live cost estimate in USD: elapsed seconds × the realtime
  /// per-minute rate. Frozen when the session stops; the actuals below take
  /// over.
  final double estimatedCost;

  /// The current (or just-finished) session's id, when a session ran.
  final String? sessionId;

  /// The session's duration in seconds, once it ended.
  final int durationSeconds;

  /// The realtime model used for the session, when known.
  final String? model;

  /// The detected (or pinned) language, when known.
  final String? language;

  /// Audio seconds billed by the realtime session, when reported.
  final int? realtimeBilledSeconds;

  /// The realtime session's actual cost in USD, when billed seconds are
  /// known.
  final double? realtimeActualCost;

  /// The estimated cost of the offered post-session diarization pass in USD
  /// — the pending offer, while the phase is [LiveSessionPhase.passOffered].
  final double? passEstimatedCost;

  /// Audio seconds billed by the post-session pass, once it ran.
  final int? passBilledSeconds;

  /// The post-session pass's actual cost in USD, once it ran.
  final double? passActualCost;

  /// Connection-interruption info for the subtle indicator.
  final ConnectionStatus connection;

  /// The current error/warning message; empty when there is none. Surfaced
  /// in the [LiveSessionPhase.error] and [LiveSessionPhase.passFailed]
  /// phases, and as a transient warning while the session runs.
  final String error;

  /// Whether the session failed to start because no API key is saved (the
  /// key's presence is checked; the key itself is never read here).
  final bool missingApiKey;

  /// Whether the app is not exempt from battery optimization — the UI shows
  /// the prompt (the session is never blocked on it).
  final bool batteryPromptNeeded;

  /// Whether the current pause was caused by another app taking audio focus
  /// (design P3-D2, live-transcription "Respect audio focus") — the UI
  /// words it differently from a user pause. Only meaningful in the
  /// [LiveSessionPhase.paused] phase.
  final bool pausedByAudioFocus;

  /// Whether [error] carries a message.
  bool get hasError => error.isNotEmpty;

  /// Returns a copy with the given fields replaced. Pass an empty string as
  /// [error] to clear it (a null argument keeps the current value).
  LiveSessionState copyWith({
    LiveSessionPhase? phase,
    List<TranscriptTurn>? turns,
    List<TranscriptGap>? gapMarkers,
    int? elapsedSeconds,
    double? estimatedCost,
    String? sessionId,
    int? durationSeconds,
    String? model,
    String? language,
    int? realtimeBilledSeconds,
    double? realtimeActualCost,
    double? passEstimatedCost,
    int? passBilledSeconds,
    double? passActualCost,
    ConnectionStatus? connection,
    String? error,
    bool? missingApiKey,
    bool? batteryPromptNeeded,
    bool? pausedByAudioFocus,
  }) =>
      LiveSessionState(
        phase: phase ?? this.phase,
        turns: turns ?? this.turns,
        gapMarkers: gapMarkers ?? this.gapMarkers,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
        estimatedCost: estimatedCost ?? this.estimatedCost,
        sessionId: sessionId ?? this.sessionId,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        model: model ?? this.model,
        language: language ?? this.language,
        realtimeBilledSeconds: realtimeBilledSeconds ?? this.realtimeBilledSeconds,
        realtimeActualCost: realtimeActualCost ?? this.realtimeActualCost,
        passEstimatedCost: passEstimatedCost ?? this.passEstimatedCost,
        passBilledSeconds: passBilledSeconds ?? this.passBilledSeconds,
        passActualCost: passActualCost ?? this.passActualCost,
        connection: connection ?? this.connection,
        error: error ?? this.error,
        missingApiKey: missingApiKey ?? this.missingApiKey,
        batteryPromptNeeded: batteryPromptNeeded ?? this.batteryPromptNeeded,
        pausedByAudioFocus: pausedByAudioFocus ?? this.pausedByAudioFocus,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveSessionState &&
          phase == other.phase &&
          elapsedSeconds == other.elapsedSeconds &&
          estimatedCost == other.estimatedCost &&
          sessionId == other.sessionId &&
          durationSeconds == other.durationSeconds &&
          model == other.model &&
          language == other.language &&
          realtimeBilledSeconds == other.realtimeBilledSeconds &&
          realtimeActualCost == other.realtimeActualCost &&
          passEstimatedCost == other.passEstimatedCost &&
          passBilledSeconds == other.passBilledSeconds &&
          passActualCost == other.passActualCost &&
          connection == other.connection &&
          error == other.error &&
          missingApiKey == other.missingApiKey &&
          batteryPromptNeeded == other.batteryPromptNeeded &&
          pausedByAudioFocus == other.pausedByAudioFocus &&
          turns.length == other.turns.length &&
          _turnsEqual(other) &&
          gapMarkers.length == other.gapMarkers.length &&
          _gapMarkersEqual(other);

  bool _turnsEqual(LiveSessionState other) {
    for (var i = 0; i < turns.length; i++) {
      if (turns[i] != other.turns[i]) {
        return false;
      }
    }
    return true;
  }

  bool _gapMarkersEqual(LiveSessionState other) {
    for (var i = 0; i < gapMarkers.length; i++) {
      if (gapMarkers[i] != other.gapMarkers[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  // Object.hash takes at most 20 positional arguments — hash the field list.
  int get hashCode => Object.hashAll([
        phase,
        turns.length,
        Object.hashAll(turns),
        gapMarkers.length,
        Object.hashAll(gapMarkers),
        elapsedSeconds,
        estimatedCost,
        sessionId,
        durationSeconds,
        model,
        language,
        realtimeBilledSeconds,
        realtimeActualCost,
        passEstimatedCost,
        passBilledSeconds,
        passActualCost,
        connection,
        error,
        missingApiKey,
        batteryPromptNeeded,
        pausedByAudioFocus,
      ]);
}

/// The clock + ticker driving the elapsed-time display. Injected so
/// controller tests are deterministic (no real timers).
abstract interface class SessionClock {
  /// The current wall-clock time.
  DateTime now();

  /// A periodic pulse (about once per second) that triggers an elapsed-time
  /// recompute. Cancelled when the session stops.
  Stream<int> ticks();
}

/// Wall-clock [SessionClock] ticking about once per second.
class SystemSessionClock implements SessionClock {
  const SystemSessionClock({this.tickInterval = const Duration(seconds: 1)});

  /// The pulse interval.
  final Duration tickInterval;

  @override
  DateTime now() => DateTime.now();

  @override
  Stream<int> ticks() => Stream<int>.periodic(tickInterval, (count) => count);
}

/// The live session controller (design P1-D7): owns [LiveSessionState] and
/// the session lifecycle — see the file comment.
class LiveSessionController extends Notifier<LiveSessionState> {
  @override
  LiveSessionState build() {
    ref.onDispose(() {
      _eventSub?.cancel();
      _tickSub?.cancel();
      _focusSub?.cancel();
      // Release the audio session if the provider is disposed mid-session
      // (the session-end teardown normally already released it).
      unawaited(_audioFocusGateway?.release());
      _audioFocusGateway = null;
      // Same for the screen wake lock held while a session runs.
      unawaited(_releaseScreenWake());
    });
    // The key's presence only — the key itself is read inside the service
    // isolate and inside the lib/mistral/ clients, never here. Tracked
    // reactively so the missing-key state follows key changes without a
    // restart (empty-error-states spec; dogfood friction 2026-10-28).
    ref.listen(apiKeyPresentProvider, (previous, next) {
      next.whenData((present) {
        if (ref.mounted) {
          _onKeyPresenceChanged(present);
        }
      });
    });
    return const LiveSessionState();
  }

  /// Keeps the missing-key state current with the key's presence: shown
  /// while no key is saved and no capture is in flight (empty-error-states
  /// spec: opening the screen with no key shows the state), dismissed as
  /// soon as a key is saved. A running session is unaffected — the next
  /// start re-checks the key.
  void _onKeyPresenceChanged(bool present) {
    if (_captureInFlight) {
      return;
    }
    final isMissingKeyState =
        state.phase == LiveSessionPhase.error && state.missingApiKey;
    if (present) {
      if (isMissingKeyState) {
        state = const LiveSessionState();
      }
    } else if (!isMissingKeyState) {
      state = const LiveSessionState(
        phase: LiveSessionPhase.error,
        error: 'No API key saved. Add your Mistral API key to start a session.',
        missingApiKey: true,
      );
    }
  }

  // -- Session-scoped private state ----------------------------------------

  StreamSubscription<SessionEvent>? _eventSub;
  StreamSubscription<int>? _tickSub;
  StreamSubscription<AudioFocusEvent>? _focusSub;
  AudioFocusGateway? _audioFocusGateway;
  Completer<void>? _sessionEnded;
  DateTime? _startedAt;

  /// Whether the screen wake lock is currently held for the running session
  /// (change 2026-10-29-keep-screen-on-during-sessions) — tracked so the
  /// release in teardown only fires when a hold actually happened.
  bool _screenWakeOn = false;

  /// When the current pause began — the elapsed clock freezes while paused
  /// (design PS-D2): the paused duration is excluded from the session time.
  DateTime? _pausedAt;

  /// Total paused duration so far this session.
  Duration _pausedAccumulated = Duration.zero;
  String? _audioPath;
  bool _turnClosed = true;

  SessionClock get _clock => ref.read(sessionClockProvider);

  /// Whether a capture session is in flight (start → the pass finishes).
  /// Starting a new session is allowed from every other phase.
  bool get _captureInFlight => switch (state.phase) {
        LiveSessionPhase.starting ||
        LiveSessionPhase.active ||
        LiveSessionPhase.paused ||
        LiveSessionPhase.stopping ||
        LiveSessionPhase.finalizing ||
        LiveSessionPhase.passRunning =>
          true,
        _ => false,
      };

  // -- Public API (the app layer's actions) --------------------------------

  /// Starts a live session. No-op while a capture session is in flight.
  ///
  /// Checks the API key's presence (never the key itself), runs the battery
  /// sanity check (never blocking: the state carries the prompt flag), and
  /// starts the capture service. [diarize] selects live speaker labelling
  /// instead of turn detection (the v1 default is turn detection, with the
  /// post-session pass for speaker attribution).
  Future<void> start({String? language, bool diarize = false}) async {
    if (_captureInFlight) {
      return;
    }
    try {
      await _start(language: language, diarize: diarize);
    } catch (e) {
      // Any start-path failure surfaces as an error state — the session
      // never hangs in the starting phase (live-transcription spec:
      // surface capture and API errors without crashing).
      await _teardown();
      state = LiveSessionState(
        phase: LiveSessionPhase.error,
        error: 'Could not start the session: $e',
      );
    }
  }

  /// The start flow, wrapped by [start] with the error state.
  Future<void> _start({String? language, bool diarize = false}) async {
    final apiKeyStore = ref.read(apiKeyStoreProvider);
    final captureService = ref.read(captureServiceProvider);
    final config = ref.read(mistralConfigProvider);

    // The key's presence only — the key itself is read inside the service
    // isolate and inside the lib/mistral/ clients, never here.
    final key = await apiKeyStore.readKey();
    if (key == null || key.isEmpty) {
      state = const LiveSessionState(
        phase: LiveSessionPhase.error,
        error: 'No API key saved. Add your Mistral API key to start a session.',
        missingApiKey: true,
      );
      return;
    }

    // Battery sanity check (live-transcription spec): never blocks the
    // session — the state carries the prompt flag and [openBatterySettings]
    // opens the system settings.
    final batteryIgnored = await captureService.isBatteryOptimizationIgnored();

    final sessionId = CaptureService.newSessionId();
    final startedAt = _clock.now();
    _startedAt = startedAt;
    _pausedAt = null;
    _pausedAccumulated = Duration.zero;
    _audioPath = null;
    _turnClosed = true;
    _sessionEnded = Completer<void>();
    state = LiveSessionState(
      phase: LiveSessionPhase.starting,
      sessionId: sessionId,
      batteryPromptNeeded: !batteryIgnored,
    );

    // Subscribe before the service starts so no event is missed.
    _eventSub = captureService.events.listen(
      (event) => unawaited(_onEvent(event)),
    );
    _tickSub = _clock.ticks().listen((_) => _onTick(config));

    final failure = await captureService.startSession(
      sessionId: sessionId,
      config: RealtimeSessionConfig(
        language: language,
        diarize: diarize,
        turnDetection: diarize ? null : const TurnDetectionConfig(),
      ),
    );
    if (failure != null) {
      await _teardown();
      state = LiveSessionState(
        phase: LiveSessionPhase.error,
        error: _startFailureMessage(failure),
      );
      return;
    }
    if (state.phase == LiveSessionPhase.error) {
      return; // a SessionError from the service already failed the start
    }
    state = state.copyWith(phase: LiveSessionPhase.active);
    // The session is capturing: configure the platform audio session for
    // recording and listen for focus changes (design P3-D2).
    await _startAudioFocusHandling();
    // Keep the display on for the whole session when the user enabled it
    // (change 2026-10-29-keep-screen-on-during-sessions); released in
    // [_teardown]. Held through pauses — a paused session is still running.
    await _enableScreenWakeIfPreferred();
  }

  /// Pauses capture and transcription; the realtime session stays open
  /// (design P1-D2). No-op unless the phase is [LiveSessionPhase.active].
  /// Clears [LiveSessionState.pausedByAudioFocus] — a user pause is not an
  /// audio-focus pause.
  Future<void> pause() async {
    if (state.phase != LiveSessionPhase.active) {
      return;
    }
    // The elapsed clock freezes from here (design PS-D2).
    _pausedAt = _clock.now();
    ref.read(captureServiceProvider).pause();
    state = state.copyWith(
      phase: LiveSessionPhase.paused,
      pausedByAudioFocus: false,
    );
  }

  /// Resumes a paused session. No-op unless the phase is
  /// [LiveSessionPhase.paused]. Clears [LiveSessionState.pausedByAudioFocus].
  Future<void> resume() async {
    if (state.phase != LiveSessionPhase.paused) {
      return;
    }
    // Fold the paused period into the accumulated pause time — the elapsed
    // clock resumes from where it froze (design PS-D2).
    final pausedAt = _pausedAt;
    if (pausedAt != null) {
      _pausedAccumulated += _clock.now().difference(pausedAt);
      _pausedAt = null;
    }
    ref.read(captureServiceProvider).resume();
    state = state.copyWith(
      phase: LiveSessionPhase.active,
      pausedByAudioFocus: false,
    );
  }

  /// Stops the session gracefully: the service ends the realtime session,
  /// closes the WAV, and forwards the final session-ended event, which
  /// finalizes the session (persistence + the pass offer). No-op unless the
  /// phase is [LiveSessionPhase.active] or [LiveSessionPhase.paused].
  Future<void> stop() async {
    final phase = state.phase;
    if (phase != LiveSessionPhase.active && phase != LiveSessionPhase.paused) {
      return;
    }
    final captureService = ref.read(captureServiceProvider);
    final timeout = ref.read(sessionFinalizeTimeoutProvider);
    final sessionEnded = _sessionEnded?.future ?? Future<void>.value();
    state = state.copyWith(phase: LiveSessionPhase.stopping);
    _tickSub?.cancel();
    _tickSub = null;
    await captureService.stop();
    try {
      await sessionEnded.timeout(timeout);
    } on TimeoutException {
      // The service stopped without forwarding the final event (killed or
      // stuck) — the session cannot be finalized.
      await _teardown();
      state = state.copyWith(
        phase: LiveSessionPhase.error,
        error: 'The capture service stopped without saving the session.',
      );
    }
  }

  /// Runs the offered post-session diarization pass (or retries it after a
  /// failure). No-op unless the phase is [LiveSessionPhase.passOffered] or
  /// [LiveSessionPhase.passFailed].
  Future<void> runDiarizationPass() async {
    final phase = state.phase;
    if (phase != LiveSessionPhase.passOffered &&
        phase != LiveSessionPhase.passFailed) {
      return;
    }
    final sessionId = state.sessionId;
    final audioPath = _audioPath;
    if (sessionId == null || audioPath == null) {
      return;
    }
    state = state.copyWith(phase: LiveSessionPhase.passRunning, error: '');
    try {
      final pass = await ref.read(diarizationPassProvider.future);
      final result = await pass.run(
        sessionId: sessionId,
        audioPath: audioPath,
        language: state.language,
      );
      _audioPath = null; // the pass deleted the audio
      state = state.copyWith(
        phase: LiveSessionPhase.done,
        turns: _finalTurns(result),
        // The labelled transcript replaces the provisional one; the
        // provisional stream's gap markers no longer apply to it.
        gapMarkers: const [],
        passBilledSeconds: result.billedAudioSeconds,
        passActualCost: result.actualCost,
        language: result.language ?? state.language,
        error: '',
      );
      // The session's status and cost changed — the history list must
      // re-read it.
      ref.invalidate(historyListProvider);
    } on MistralApiException catch (e) {
      // The provisional transcript is preserved; the audio is kept for the
      // retry.
      state = state.copyWith(phase: LiveSessionPhase.passFailed, error: e.message);
    } catch (e) {
      state = state.copyWith(
        phase: LiveSessionPhase.passFailed,
        error: 'The speaker-attribution pass failed: $e',
      );
    }
  }

  /// Skips the offered pass: the provisional transcript is the transcript of
  /// record and the session audio is kept (the pass can still be run later).
  /// No-op unless the phase is [LiveSessionPhase.passOffered].
  Future<void> skipDiarizationPass() async {
    if (state.phase != LiveSessionPhase.passOffered) {
      return;
    }
    state = state.copyWith(phase: LiveSessionPhase.done);
  }

  /// Opens the system battery-optimization settings (the battery-prompt
  /// action; the prompt UI itself is the app layer's).
  Future<void> openBatterySettings() async {
    await ref.read(captureServiceProvider).openBatteryOptimizationSettings();
  }

  /// Re-checks the battery-optimization exemption (live-transcription
  /// spec: the check runs at session start and while a session is active
  /// — and is repeated when the app returns to the foreground, so the
  /// prompt is dismissed once the user has granted the exemption; dogfood
  /// friction 2026-10-28). Never raises the prompt without a session
  /// context: with no capture in flight and the prompt not showing, the
  /// platform is not queried.
  Future<void> recheckBatteryExemption() async {
    if (!_captureInFlight && !state.batteryPromptNeeded) {
      return;
    }
    final ignored =
        await ref.read(captureServiceProvider).isBatteryOptimizationIgnored();
    if (!ref.mounted) {
      return;
    }
    final needed = !ignored;
    if (state.batteryPromptNeeded != needed) {
      state = state.copyWith(batteryPromptNeeded: needed);
    }
  }

  /// Re-requests the RECORD_AUDIO runtime permission — the remedy action of
  /// the mic-permission-denied state (Phase 3 group 2). Returns whether the
  /// permission is now granted; the gateway prompts natively.
  Future<bool> requestMicPermission() =>
      ref.read(foregroundTaskGatewayProvider).requestRecordAudioPermission();

  // -- Event handling --------------------------------------------------------

  Future<void> _onEvent(SessionEvent event) async {
    switch (event) {
      case SessionTextDelta(:final text):
        // The paused period produces no transcript text (live-transcription
        // spec) — even if the service were to forward a stray delta.
        if (state.phase == LiveSessionPhase.paused) {
          return;
        }
        _appendText(text, speakerLabel: null);
      case SessionSpeakerSegment(:final text, :final speakerId):
        if (state.phase == LiveSessionPhase.paused) {
          return;
        }
        _appendText(text, speakerLabel: speakerId);
      case SessionTurnStarted():
        // A turn boundary closes the current block. The pause is silence and
        // closes the turn the same way — the transcript shows the pause as a
        // turn boundary (design P1-D2).
        _closeTurn();
      case SessionTurnEnded():
        _closeTurn();
      case SessionReconnected(:final dropReason):
        final connection = state.connection;
        final running =
            state.phase == LiveSessionPhase.active ||
            state.phase == LiveSessionPhase.paused;
        state = state.copyWith(
          connection: connection.copyWith(
            reconnectCount: connection.reconnectCount + 1,
            lastDropReason: dropReason ?? connection.lastDropReason,
          ),
          // A recovered blip clears a transient warning (only while running).
          error: running ? '' : state.error,
        );
      case SessionBufferedAudioReplayed(:final seconds):
        state = state.copyWith(
          connection: state.connection.copyWith(lastReplayedSeconds: seconds),
        );
      case SessionBufferedAudioDropped(:final seconds):
        // The transcript shows a visible gap marker at the drop position
        // (live-transcription spec); the status row carries the totals.
        _recordGap(seconds);
        state = state.copyWith(
          connection: state.connection.copyWith(lastDroppedSeconds: seconds),
        );
      case SessionTranscriptionDone(:final usage, :final model, :final language):
        if (!_captureInFlight) {
          return;
        }
        _applyRealtimeUsage(usage, model: model, language: language);
      case SessionEnded():
        await _finalize(event);
      case SessionError(:final message):
        await _onServiceError(message);
    }
  }

  /// A SessionError is fatal while the session is starting (the service's
  /// failure path — missing key, corrupt config, session-start failure —
  /// stops the service); while running it is a transient warning (the client
  /// reconnects on connection errors), surfaced outside the transcript.
  Future<void> _onServiceError(String message) async {
    switch (state.phase) {
      case LiveSessionPhase.starting:
        await _teardown();
        state = LiveSessionState(phase: LiveSessionPhase.error, error: message);
      case LiveSessionPhase.active ||
          LiveSessionPhase.paused ||
          LiveSessionPhase.stopping ||
          LiveSessionPhase.finalizing:
        if (state.error.isEmpty) {
          state = state.copyWith(error: message);
        }
      default:
        break; // no session in flight — nothing to warn about
    }
  }

  void _applyRealtimeUsage(Usage usage, {required String model, String? language}) {
    final billed = usage.promptAudioSeconds;
    final config = ref.read(mistralConfigProvider);
    state = state.copyWith(
      realtimeBilledSeconds: billed,
      realtimeActualCost:
          billed == null ? null : billed / 60 * config.realtimeRatePerMinute,
      model: model.isEmpty ? null : model,
      language: language ?? state.language,
    );
  }

  void _onTick(MistralConfig config) {
    final startedAt = _startedAt;
    if (startedAt == null) {
      return;
    }
    // The clock advances only while capturing: a paused period is excluded
    // from the session time, and the estimate (elapsed × rate) accrues only
    // while capture is active — nothing is sent or billed while paused
    // (design PS-D2).
    if (state.phase != LiveSessionPhase.active) {
      return;
    }
    final elapsed =
        (_clock.now().difference(startedAt) - _pausedAccumulated).inSeconds;
    if (elapsed == state.elapsedSeconds) {
      return;
    }
    state = state.copyWith(
      elapsedSeconds: elapsed,
      estimatedCost: elapsed / 60 * config.realtimeRatePerMinute,
    );
  }

  // -- Audio focus (design P3-D2, task 3.2) ----------------------------------

  /// Configures the platform audio session for recording and subscribes to
  /// focus changes (live-transcription spec "Respect audio focus"). Called
  /// when the session becomes active; the symmetric [_stopAudioFocusHandling]
  /// runs at teardown.
  Future<void> _startAudioFocusHandling() async {
    final gateway = ref.read(audioFocusGatewayProvider);
    _audioFocusGateway = gateway;
    await gateway.configureForRecord();
    _focusSub = gateway.focusEvents.listen(
      (event) => unawaited(_onAudioFocusEvent(event)),
    );
  }

  /// Cancels the focus subscription and releases the audio session (the
  /// symmetric teardown of [_startAudioFocusHandling]).
  Future<void> _stopAudioFocusHandling() async {
    await _focusSub?.cancel();
    _focusSub = null;
    final gateway = _audioFocusGateway;
    _audioFocusGateway = null;
    await gateway?.release();
  }

  /// A platform audio-focus change (design P3-D2): a focus loss pauses
  /// capture through the existing pause path — the capture service pauses,
  /// the phase becomes paused, the session stays open — and a focus return
  /// resumes, but only when the pause was caused by the focus loss (a
  /// user-paused session stays paused). Ignored when no session is active.
  Future<void> _onAudioFocusEvent(AudioFocusEvent event) async {
    switch (event) {
      case AudioFocusEvent.lost:
        if (state.phase == LiveSessionPhase.active) {
          await pause();
          state = state.copyWith(pausedByAudioFocus: true);
        }
      case AudioFocusEvent.gained:
        if (state.phase == LiveSessionPhase.paused &&
            state.pausedByAudioFocus) {
          await resume();
        }
    }
  }

  // -- Turn grouping (design P1-D7) -----------------------------------------

  /// Appends one piece of transcript text to the current turn, starting a new
  /// turn (block) when the previous one is closed or the speaker changed
  /// (diarize mode).
  void _appendText(String text, {required String? speakerLabel}) {
    if (text.isEmpty) {
      return;
    }
    final turns = List<TranscriptTurn>.of(state.turns);
    if (turns.isNotEmpty && !_turnClosed) {
      final last = turns.last;
      final speakerChanged =
          speakerLabel != null && last.speakerLabel != speakerLabel;
      if (!speakerChanged) {
        turns[turns.length - 1] = last.copyWith(text: last.text + text);
        state = state.copyWith(turns: turns);
        return;
      }
    }
    turns.add(TranscriptTurn(speakerLabel: speakerLabel, text: text));
    _turnClosed = false;
    state = state.copyWith(turns: turns);
  }

  /// Closes the current turn block (a turn boundary — turn start/end, or the
  /// pause, which is silence). An empty trailing turn carries no text and is
  /// dropped.
  void _closeTurn() {
    _turnClosed = true;
    final turns = state.turns;
    if (turns.isNotEmpty && turns.last.text.isEmpty) {
      state = state.copyWith(turns: List<TranscriptTurn>.of(turns)..removeLast());
    }
  }

  /// Records a transcript gap marker at the drop position: the currently open
  /// turn is closed so the marker renders between the text transcribed
  /// before and after the lost audio (live-transcription spec: "the
  /// transcript SHALL show a visible gap marker at the point where audio was
  /// lost").
  void _recordGap(double seconds) {
    if (seconds <= 0) {
      return;
    }
    _closeTurn();
    state = state.copyWith(
      gapMarkers: List<TranscriptGap>.of(state.gapMarkers)
        ..add(TranscriptGap(
          afterTurnIndex: state.turns.length - 1,
          droppedSeconds: seconds,
        )),
    );
  }

  /// The labelled turns that replace the provisional transcript after a
  /// successful pass.
  static List<TranscriptTurn> _finalTurns(DiarizationPassResult result) {
    if (result.segments.isNotEmpty) {
      return <TranscriptTurn>[
        for (final segment in result.segments)
          TranscriptTurn(
            speakerLabel: segment.speakerId,
            text: segment.text,
            isProvisional: false,
          ),
      ];
    }
    if (result.text.isNotEmpty) {
      return <TranscriptTurn>[TranscriptTurn(text: result.text, isProvisional: false)];
    }
    return const [];
  }

  // -- Finalization (task 4.4) -----------------------------------------------

  /// Finalizes the session on the service's final session-ended event: saves
  /// the session + segments + audio path via the repository (status
  /// provisional), then offers the diarization pass with its estimated cost.
  /// Runs on the graceful stop; also when the notification stop button ends
  /// the session without the UI calling [stop].
  Future<void> _finalize(SessionEnded event) async {
    switch (state.phase) {
      case LiveSessionPhase.active ||
          LiveSessionPhase.paused ||
          LiveSessionPhase.stopping:
        break; // a session is in flight
      default:
        return; // no session to finalize
    }
    final startedAt = _startedAt;
    final durationSeconds = startedAt == null
        ? 0
        // The session duration is the active capture time — paused periods
        // are excluded (design PS-D2), matching the billed audio.
        : (_clock.now().difference(startedAt) - _pausedAccumulated)
            .inSeconds;
    // The sync prefix: flip the phase and unblock stop() before the first
    // await, so a second session-ended event is ignored.
    state = state.copyWith(
      phase: LiveSessionPhase.finalizing,
      sessionId: event.sessionId,
      durationSeconds: durationSeconds,
    );
    _sessionEnded?.complete();
    await _teardown();

    final repository = ref.read(sessionRepositoryProvider);
    final config = ref.read(mistralConfigProvider);
    final billedAudioSeconds = event.usage.promptAudioSeconds;
    final realtimeCost = billedAudioSeconds == null
        ? null
        : billedAudioSeconds / 60 * config.realtimeRatePerMinute;
    state = state.copyWith(
      model: event.model.isEmpty ? null : event.model,
      language: event.language ?? state.language,
      realtimeBilledSeconds: billedAudioSeconds,
      realtimeActualCost: realtimeCost,
    );

    try {
      await repository.saveSession(
        StoredSession(
          id: event.sessionId,
          startedAt: startedAt ?? _clock.now(),
          durationSeconds: durationSeconds,
          model: event.model,
          status: SessionStatus.provisional,
          billedAudioSeconds: billedAudioSeconds,
          actualCost: realtimeCost,
          language: event.language,
          audioPath: event.audioPath,
        ),
        _storedSegments(event),
      );
    } catch (e) {
      state = state.copyWith(
        phase: LiveSessionPhase.error,
        error: 'Could not save the session: $e',
      );
      return;
    }
    // The saved session must show up in the history list (it may be open
    // underneath — e.g. the notification's stop ended the session).
    ref.invalidate(historyListProvider);

    // Offer the pass: the estimated cost is the saved audio's duration times
    // the configured batch Mini rate (cost-indicator spec).
    _audioPath = event.audioPath.isEmpty ? null : event.audioPath;
    try {
      final pass = await ref.read(diarizationPassProvider.future);
      final estimate = await pass.estimateCost(event.audioPath);
      state = state.copyWith(
        phase: LiveSessionPhase.passOffered,
        passEstimatedCost: estimate,
      );
    } catch (e) {
      // The transcript is saved; the pass could not be offered (e.g. the
      // audio file is unreadable) — the session completes with a warning.
      state = state.copyWith(
        phase: LiveSessionPhase.done,
        error:
            'Session saved, but the speaker-attribution pass could not be '
            'offered: $e',
      );
    }
  }

  /// Maps the final event's realtime segments to stored segments, persisting
  /// what exists — realtime segments carry no timestamps and, in turn
  /// detection mode, no speaker labels — and falling back to the full text
  /// when the API reported no segments.
  static List<StoredSegment> _storedSegments(SessionEnded event) {
    if (event.segments.isNotEmpty) {
      return <StoredSegment>[
        for (var i = 0; i < event.segments.length; i++)
          StoredSegment(
            sessionId: event.sessionId,
            order: i,
            text: event.segments[i].text,
            speakerLabel: event.segments[i].speakerId,
            startSeconds: event.segments[i].start,
            endSeconds: event.segments[i].end,
          ),
      ];
    }
    if (event.fullText.isNotEmpty) {
      return <StoredSegment>[
        StoredSegment(
          sessionId: event.sessionId,
          order: 0,
          text: event.fullText,
        ),
      ];
    }
    return const [];
  }

  // -- Screen wake (change 2026-10-29-keep-screen-on-during-sessions) --------

  /// Holds the screen wake lock when the persisted "Keep screen on during
  /// sessions" preference is on. Called when the session becomes active.
  /// Best-effort: a screen-wake failure never fails the session.
  Future<void> _enableScreenWakeIfPreferred() async {
    final preferences = await ref.read(preferencesProvider.future);
    if (!preferences.keepScreenOn || _screenWakeOn) {
      return;
    }
    _screenWakeOn = true;
    try {
      await ref.read(screenWakeGatewayProvider).setScreenOn(true);
    } catch (_) {
      // Best-effort: the display simply times out normally.
    }
  }

  /// Releases the screen wake lock if it is held. Best-effort, idempotent.
  Future<void> _releaseScreenWake() async {
    if (!_screenWakeOn) {
      return;
    }
    _screenWakeOn = false;
    try {
      await ref.read(screenWakeGatewayProvider).setScreenOn(false);
    } catch (_) {
      // Best-effort: the window flag dies with the process anyway.
    }
  }

  // -- Teardown ----------------------------------------------------------------

  Future<void> _teardown() async {
    await _eventSub?.cancel();
    _eventSub = null;
    await _tickSub?.cancel();
    _tickSub = null;
    await _stopAudioFocusHandling();
    await _releaseScreenWake();
    _sessionEnded = null;
    _startedAt = null;
    _audioPath = null;
    _turnClosed = true;
  }

  static String _startFailureMessage(CaptureStartFailure failure) => switch (failure) {
        MicPermissionDenied() =>
          'Microphone permission denied. Grant it to record a session.',
        NotificationPermissionDenied() =>
          'Notification permission denied. The capture notification needs it.',
        ServiceStartFailed(:final error) =>
          'Could not start the capture service: $error',
      };
}
