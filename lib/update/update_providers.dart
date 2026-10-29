// Riverpod wiring for the update tracker (change
// 2026-10-29-update-tracker, tasks 5.1-5.3, design decisions 7-11,
// 15-16): the persisted update-check state, the GitHub Releases client,
// the platform seams, the recording gate, and the update check
// controller — mirroring session_providers.dart's style.
//
// The home screen fires [updateCheckOnStartProvider] once per app run
// (design decision 10) and presents the update dialog from
// [updateCheckControllerProvider]'s state; the settings screen's Updates
// section runs the manual check through the same controller (design
// decision 14). The controller's dependencies are resolved from this
// graph (Riverpod 3's NotifierProvider create function receives no ref —
// see the controller's file comment), so the seam overrides in tests flow
// into the controller.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../session/live_session_controller.dart';
import '../session/session_providers.dart';
import '../storage/storage.dart';
import 'app_version_reader.dart';
import 'dio_update_check_client.dart';
import 'update_check_client.dart';
import 'update_check_controller.dart';
import 'url_opener.dart';

/// The persisted update-check state (design decision 6), backed by the
/// app's Drift database — shared with the session repositories.
final updateStateRepositoryProvider = Provider<UpdateStateRepository>(
    (ref) => DriftUpdateStateRepository(ref.watch(appDatabaseProvider)));

/// The GitHub Releases client (design decisions 1-2, 5).
final updateCheckClientProvider =
    Provider<UpdateCheckClient>((ref) => DioUpdateCheckClient());

/// The installed-version seam (design decisions 3, 11).
final appVersionReaderProvider =
    Provider<AppVersionReader>((ref) => PackageInfoAppVersionReader());

/// The URL-opener seam (design decisions 4, 11).
final urlOpenerProvider = Provider<UrlOpener>((ref) => UrlLauncherUrlOpener());

/// The installed app's version. Cached forever: the version cannot change
/// while the app runs (design decision 3).
final installedVersionProvider = FutureProvider<String>(
    (ref) => ref.watch(appVersionReaderProvider).readVersionName());

/// Whether a live transcription session is currently recording (design
/// decision 9): the automatic start check suppresses the update dialog
/// while a session is recording, without marking the version notified.
/// The update controller receives this as a plain `bool Function()`
/// callback — the lib/session read lives here, keeping lib/update
/// decoupled from lib/session.
bool isSessionRecording(Ref ref) {
  // Read (not watch): the gate is consulted at check time, and watching
  // would subscribe the caller to every live-session state change,
  // rebuilding (and resetting) the update controller's state on each
  // phase change.
  final phase = ref.read(liveSessionControllerProvider).phase;
  return phase == LiveSessionPhase.starting ||
      phase == LiveSessionPhase.active ||
      phase == LiveSessionPhase.paused;
}

/// The update check controller (design decisions 7-11, 15-16).
final updateCheckControllerProvider =
    NotifierProvider<UpdateCheckController, UpdateCheckState>(
        UpdateCheckController.new);

/// Fires the throttled, silent start check once per app run (design
/// decision 10): the home screen watches this on first build.
/// [UpdateCheckController.checkOnStart] never throws, so this
/// FutureProvider never errors.
final updateCheckOnStartProvider = FutureProvider<void>(
    (ref) => ref.read(updateCheckControllerProvider.notifier).checkOnStart());
