// The update check controller (change 2026-10-29-update-tracker, tasks
// 5.1-5.3, design decisions 7-11 and 15-16): a Riverpod notifier owning
// the update-check state — [UpdateCheckState] is what the home screen's
// update dialog and the settings screen's Updates section render.
//
// Two checks run against the GitHub Releases seam ([UpdateCheckClient]):
//
// - [checkOnStart] — the automatic check at app start (design decisions
//   7, 10): throttled to at most one network request per 24 hours per
//   install, and fully silent — every error path (network, malformed
//   response, storage) is caught and surfaces nothing. Only a
//   well-formed response advances the persisted last-check time, so a
//   failed check is retried on the next app start (spec: "Check for a
//   newer release on app start"). A newer, not-yet-notified version is
//   published as [UpdateCheckState.available] — unless a live session is
//   recording: the recording gate is an injected `bool Function()`
//   callback so this layer stays decoupled from lib/session (design
//   decision 9), and the version is NOT marked notified in that case, so
//   a later app start shows it.
// - [checkNow] — the manual "Check for updates" action (design decisions
//   14-16): bypasses the throttle, advances the persisted last-check
//   time on a well-formed response, and reports the outcome — update
//   available (published even when that version was already notified and
//   while recording: the check was explicitly requested), up to date, or
//   failed with a retryable message.
//
// The dialog's two actions both record the available version as notified
// (design decision 8): [dismissUpdate] ("Later") and [openRelease] ("Open
// release" — opens the release page through the [UrlOpener] seam, then
// dismisses).
//
// The dependencies are constructor-injected so the controller tests drive
// the whole flow through the fakes in test/update/fakes.dart. Riverpod
// 3's NotifierProvider create function receives no ref, so the production
// wiring cannot pass provider-resolved dependencies to the constructor;
// [build] resolves any dependency the constructor did not receive from
// the provider graph in update_providers.dart — which is also what makes
// the seam-provider overrides flow into the controller.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../session/live_session_controller.dart';
import '../session/session_providers.dart';
import '../storage/storage.dart';
import 'app_version_reader.dart';
import 'update_check_client.dart';
import 'update_config.dart';
import 'update_providers.dart';
import 'url_opener.dart';

/// The outcome of a manual update check ([UpdateCheckController.checkNow]).
enum UpdateCheckOutcome {
  /// A newer version is available — [UpdateCheckState.available] is set
  /// and the update dialog is shown.
  updateAvailable,

  /// The installed version is the latest release.
  upToDate,

  /// The check failed (network, API, or malformed response) —
  /// [UpdateCheckState.errorMessage] carries a retryable message.
  failed,
}

/// The immutable, UI-ready state of the update check (design decisions
/// 10, 14-16): a screen renders it directly. Value equality: two states
/// with the same content are equal.
class UpdateCheckState {
  const UpdateCheckState({
    this.checking = false,
    this.outcome,
    this.available,
    this.installedVersion,
    this.errorMessage,
  });

  /// Whether a manual check is running (design decision 14: the settings
  /// button is disabled with a progress indicator while checking).
  final bool checking;

  /// The last manual-check outcome, or null when no manual check has
  /// completed — the automatic start check reports nothing.
  final UpdateCheckOutcome? outcome;

  /// A newer version to notify about — drives the update dialog.
  final UpdateInfo? available;

  /// The installed app's version, once a check has read it.
  final String? installedVersion;

  /// The manual check's failure message, when [outcome] is
  /// [UpdateCheckOutcome.failed].
  final String? errorMessage;

  /// Whether an update dialog should be presented.
  bool get hasUpdate => available != null;

  /// Sentinel for [copyWith]: omit the argument to keep the current
  /// value; pass an explicit null to clear a nullable field.
  static const Object _keep = Object();

  /// Returns a copy with the given fields replaced. Nullable fields are
  /// cleared by passing an explicit null (see [_keep]).
  UpdateCheckState copyWith({
    bool? checking,
    Object? outcome = _keep,
    Object? available = _keep,
    Object? installedVersion = _keep,
    Object? errorMessage = _keep,
  }) =>
      UpdateCheckState(
        checking: checking ?? this.checking,
        outcome:
            outcome == _keep ? this.outcome : outcome as UpdateCheckOutcome?,
        available:
            available == _keep ? this.available : available as UpdateInfo?,
        installedVersion: installedVersion == _keep
            ? this.installedVersion
            : installedVersion as String?,
        errorMessage: errorMessage == _keep
            ? this.errorMessage
            : errorMessage as String?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UpdateCheckState &&
          checking == other.checking &&
          outcome == other.outcome &&
          available == other.available &&
          installedVersion == other.installedVersion &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode =>
      Object.hash(checking, outcome, available, installedVersion, errorMessage);
}

/// The update check controller (design decisions 7-11, 15-16): owns
/// [UpdateCheckState] — see the file comment.
class UpdateCheckController extends Notifier<UpdateCheckState> {
  /// Creates the controller. Tests inject every dependency (the fakes
  /// from test/update/fakes.dart, a controllable clock, an in-memory
  /// repository, and a controllable recording gate); the production
  /// provider passes none and [build] resolves them from the provider
  /// graph (see the file comment).
  UpdateCheckController({
    UpdateCheckClient? client,
    AppVersionReader? versionReader,
    UrlOpener? urlOpener,
    UpdateStateRepository? stateRepository,
    SessionClock? clock,
    bool Function()? isRecording,
  })  : _injectedClient = client,
        _injectedVersionReader = versionReader,
        _injectedUrlOpener = urlOpener,
        _injectedStateRepository = stateRepository,
        _injectedClock = clock,
        _injectedIsRecording = isRecording;

  final UpdateCheckClient? _injectedClient;
  final AppVersionReader? _injectedVersionReader;
  final UrlOpener? _injectedUrlOpener;
  final UpdateStateRepository? _injectedStateRepository;
  final SessionClock? _injectedClock;
  final bool Function()? _injectedIsRecording;

  late final UpdateCheckClient _client;
  late final AppVersionReader _versionReader;
  late final UrlOpener _urlOpener;
  late final UpdateStateRepository _stateRepository;
  late final SessionClock _clock;
  late final bool Function() _isRecording;

  /// The manual check's failure wording (design decision 16: the settings
  /// screen's existing error banner taxonomy, with a retry action).
  static const String checkFailedMessage =
      'Could not check for updates. Check your connection and try again.';

  @override
  UpdateCheckState build() {
    // Resolve any dependency the constructor did not receive from the
    // provider graph (the production wiring); tests inject all of them
    // and never reach this. Read (not watch): nothing here should rebuild
    // — and reset — the controller's state.
    _client = _injectedClient ?? ref.read(updateCheckClientProvider);
    _versionReader =
        _injectedVersionReader ?? ref.read(appVersionReaderProvider);
    _urlOpener = _injectedUrlOpener ?? ref.read(urlOpenerProvider);
    _stateRepository =
        _injectedStateRepository ?? ref.read(updateStateRepositoryProvider);
    _clock = _injectedClock ?? ref.read(sessionClockProvider);
    _isRecording =
        _injectedIsRecording ?? () => isSessionRecording(ref);
    return const UpdateCheckState();
  }

  // -- Public API (the app layer's actions) --------------------------------

  /// The automatic check at app start (design decisions 7, 10): throttled
  /// to one request per 24 hours, fully silent — this never throws and
  /// never surfaces an error, dialog, or retry prompt. Only a well-formed
  /// response advances the persisted last-check time (a failed check is
  /// retried on the next start). A newer, not-yet-notified version is
  /// published as [UpdateCheckState.available] unless a live session is
  /// recording (the version is not marked notified in that case, so a
  /// later start shows it — spec: "Show the update dialog once per
  /// version").
  Future<void> checkOnStart() async {
    try {
      final stored = await _stateRepository.loadUpdateState();
      final lastCheckAtMs = stored.lastCheckAtMs;
      if (lastCheckAtMs != null &&
          _clock.now().millisecondsSinceEpoch - lastCheckAtMs <
              UpdateConfig.checkThrottle.inMilliseconds) {
        return; // throttled — no network request
      }
      final info = await _client.fetchLatestRelease();
      if (info == null) {
        // Failed or malformed response: the last-check time is NOT
        // advanced, so the next app start retries (design decision 7).
        return;
      }
      // A well-formed response advances the persisted last-check time
      // (merged with the stored notified version — saveUpdateState
      // replaces the row).
      await _stateRepository.saveUpdateState(StoredUpdateState(
        lastCheckAtMs: _clock.now().millisecondsSinceEpoch,
        lastNotifiedVersion: stored.lastNotifiedVersion,
      ));
      final installed = await _versionReader.readVersionName();
      if (!isNewerVersion(info.version, installed)) {
        return; // up to date (or a version that cannot be parsed)
      }
      if (stored.lastNotifiedVersion == info.version) {
        return; // already notified — the dialog is shown once per version
      }
      if (_isRecording()) {
        // Suppressed while recording; NOT marked notified, so a later
        // app start shows it (design decision 9).
        return;
      }
      if (!ref.mounted) {
        return;
      }
      state = state.copyWith(available: info, installedVersion: installed);
    } catch (_) {
      // Silent failure everywhere (design decision 13): the start check
      // is ambient — an error would be noise.
    }
  }

  /// The manual "Check for updates" action (design decisions 14-16):
  /// an immediate check that bypasses the 24-hour throttle. Reports the
  /// outcome through the state: [UpdateCheckOutcome.updateAvailable]
  /// (publishing [UpdateCheckState.available] even when that version was
  /// already notified and while a session is recording — explicit user
  /// intent), [UpdateCheckOutcome.upToDate], or
  /// [UpdateCheckOutcome.failed] with a retryable message. A well-formed
  /// response advances the persisted last-check time; a failed check does
  /// not. No-op while a check is already running.
  Future<void> checkNow() async {
    if (state.checking) {
      return; // a check is already running — no second concurrent check
    }
    state = state.copyWith(checking: true, outcome: null, errorMessage: null);
    try {
      final info = await _client.fetchLatestRelease();
      if (info == null) {
        // Failed or malformed response: the last-check time is NOT
        // advanced.
        if (ref.mounted) {
          state = state.copyWith(
            checking: false,
            outcome: UpdateCheckOutcome.failed,
            errorMessage: checkFailedMessage,
          );
        }
        return;
      }
      final stored = await _stateRepository.loadUpdateState();
      await _stateRepository.saveUpdateState(StoredUpdateState(
        lastCheckAtMs: _clock.now().millisecondsSinceEpoch,
        lastNotifiedVersion: stored.lastNotifiedVersion,
      ));
      final installed = await _versionReader.readVersionName();
      if (!ref.mounted) {
        return;
      }
      if (isNewerVersion(info.version, installed)) {
        // Explicit user intent: shown even when already notified and
        // while recording (spec: "Report the outcome of a manual check").
        state = state.copyWith(
          checking: false,
          outcome: UpdateCheckOutcome.updateAvailable,
          available: info,
          installedVersion: installed,
        );
      } else {
        state = state.copyWith(
          checking: false,
          outcome: UpdateCheckOutcome.upToDate,
          installedVersion: installed,
        );
      }
    } catch (e) {
      if (ref.mounted) {
        state = state.copyWith(
          checking: false,
          outcome: UpdateCheckOutcome.failed,
          errorMessage: 'Could not check for updates: $e',
        );
      }
    }
  }

  /// Dismisses the update dialog ("Later"): records the available
  /// version as notified (merged into the stored row) and clears
  /// [UpdateCheckState.available]. No-op when no update is published.
  /// Errors are caught silently (design decision 13).
  Future<void> dismissUpdate() async {
    final available = state.available;
    if (available == null) {
      return;
    }
    try {
      final stored = await _stateRepository.loadUpdateState();
      await _stateRepository.saveUpdateState(StoredUpdateState(
        lastCheckAtMs: stored.lastCheckAtMs,
        lastNotifiedVersion: available.version,
      ));
      if (ref.mounted) {
        state = state.copyWith(available: null);
      }
    } catch (_) {
      // Silent: the notification is best-effort (design decision 13).
    }
  }

  /// The dialog's primary action ("Open release"): opens the available
  /// version's release page in the device's browser through the
  /// [UrlOpener] seam, then dismisses — both dialog actions record the
  /// version as notified (design decision 8). A URL that cannot be opened
  /// neither crashes the app nor blocks the dismissal (spec: "Open the
  /// release page in the browser").
  Future<void> openRelease() async {
    final available = state.available;
    if (available == null) {
      return;
    }
    try {
      await _urlOpener.open(available.releasePageUrl);
    } catch (_) {
      // The seam's contract is a plain bool, but a throwing opener must
      // not crash the app or leave the dialog stuck.
    }
    await dismissUpdate();
  }
}
