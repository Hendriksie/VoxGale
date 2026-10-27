// The audio-focus seam (design P3-D2, task 3.1): the app's boundary to the
// platform's audio-focus state. `audio_session` is a platform channel — it
// cannot run in unit tests — so the live session controller drives
// pause-on-focus-loss through this interface and the tests inject a fake
// (the project's inject-a-seam rule). The production implementation wraps
// the audio_session plugin; the focus events it reports are what the
// live-transcription spec's "Respect audio focus" requirement needs: pause
// capture when another app takes audio focus (e.g. an incoming phone call),
// resume when focus returns.

import 'dart:async';

import 'package:audio_session/audio_session.dart';

/// A platform audio-focus change reported to the app.
enum AudioFocusEvent {
  /// Another application took audio focus (an interruption began — e.g. an
  /// incoming phone call or another recorder).
  lost,

  /// Audio focus returned to the app (the interruption ended).
  gained,
}

/// The audio-focus seam (design P3-D2): configures the platform's audio
/// session for recording and reports focus changes as [AudioFocusEvent]s.
abstract interface class AudioFocusGateway {
  /// Configures the platform audio session for recording and activates it
  /// (requesting audio focus), so focus changes are reported on
  /// [focusEvents]. Called when a capture session becomes active.
  Future<void> configureForRecord();

  /// Focus changes: [AudioFocusEvent.lost] when another app takes audio
  /// focus, [AudioFocusEvent.gained] when focus returns. Broadcast, no
  /// replay: subscribe before [configureForRecord].
  Stream<AudioFocusEvent> get focusEvents;

  /// Releases the audio session (abandons audio focus) and stops reporting
  /// focus changes. Called when the capture session ends. Idempotent.
  Future<void> release();
}

/// [AudioFocusGateway] backed by the audio_session plugin (a platform
/// channel — never constructed in unit tests; the tests use a fake).
class AudioSessionFocusGateway implements AudioFocusGateway {
  AudioSession? _session;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  final StreamController<AudioFocusEvent> _focusEvents =
      StreamController<AudioFocusEvent>.broadcast();

  @override
  Future<void> configureForRecord() async {
    final session = _session ??= await AudioSession.instance;
    // A recording configuration: voice-communication usage (a call-like
    // audio stream — the closest platform match to transcription capture)
    // and pause-when-ducked, so a transient focus loss arrives as a pause
    // interruption rather than a duck.
    await session.configure(const AudioSessionConfiguration(
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        usage: AndroidAudioUsage.voiceCommunication,
      ),
      androidWillPauseWhenDucked: true,
    ));
    // Activating the session is what requests audio focus and registers
    // the platform's focus-change callback — without it no interruption
    // events are delivered.
    await session.setActive(true);
    _interruptionSub ??= session.interruptionEventStream.listen(_onInterruption);
  }

  @override
  Stream<AudioFocusEvent> get focusEvents => _focusEvents.stream;

  @override
  Future<void> release() async {
    await _interruptionSub?.cancel();
    _interruptionSub = null;
    final session = _session;
    _session = null;
    if (session != null) {
      // Deactivating the session abandons audio focus on Android.
      await session.setActive(false);
    }
  }

  /// Maps a platform interruption to a focus event: an interruption that
  /// begins is a focus loss (the app can no longer record); one that ends
  /// is the focus returning.
  void _onInterruption(AudioInterruptionEvent event) {
    _focusEvents.add(event.begin ? AudioFocusEvent.lost : AudioFocusEvent.gained);
  }
}
