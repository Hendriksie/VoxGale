// Unit tests for [UpdateCheckController] (change
// 2026-10-29-update-tracker, tasks 5.1 and 5.3): the throttled, silent
// start check and the manual check, driven through the fakes in
// fakes.dart plus a controllable clock, an in-memory
// [UpdateStateRepository], and a controllable recording gate — the
// controller never touches the network or a platform channel here (the
// production implementations have their own direct coverage: the Drift
// repository in test/storage/, the dio client in
// dio_update_check_client_test.dart).

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxgale/session/live_session_controller.dart';
import 'package:voxgale/storage/storage.dart';
import 'package:voxgale/update/update_check_client.dart';
import 'package:voxgale/update/update_check_controller.dart';
import 'package:voxgale/update/update_config.dart';
import 'package:voxgale/update/update_providers.dart';

import 'fakes.dart';

/// Deterministic [SessionClock]: the test sets the time (no real timers).
class FakeUpdateClock implements SessionClock {
  FakeUpdateClock() : nowValue = DateTime(2026, 10, 29, 12, 0, 0);

  DateTime nowValue;

  @override
  DateTime now() => nowValue;

  @override
  Stream<int> ticks() => const Stream<int>.empty();

  void advance(Duration duration) => nowValue = nowValue.add(duration);
}

/// In-memory [UpdateStateRepository] for tests.
class InMemoryUpdateStateRepository implements UpdateStateRepository {
  StoredUpdateState stored = const StoredUpdateState();

  @override
  Future<StoredUpdateState> loadUpdateState() async => stored;

  @override
  Future<void> saveUpdateState(StoredUpdateState state) async {
    stored = state;
  }
}

/// An [UpdateStateRepository] test double whose load always throws (a
/// storage failure).
class ThrowingUpdateStateRepository implements UpdateStateRepository {
  @override
  Future<StoredUpdateState> loadUpdateState() async =>
      throw StateError('storage down (test)');

  @override
  Future<void> saveUpdateState(StoredUpdateState state) async {}
}

/// A [UpdateCheckClient] test double whose response the test gates behind
/// a completer (to hold a check in flight).
class GatedUpdateCheckClient implements UpdateCheckClient {
  final Completer<UpdateInfo?> completer = Completer<UpdateInfo?>();

  /// How many times [fetchLatestRelease] was called.
  int callCount = 0;

  void complete(UpdateInfo? info) => completer.complete(info);

  @override
  Future<UpdateInfo?> fetchLatestRelease() {
    callCount++;
    return completer.future;
  }
}

/// A [UpdateCheckClient] test double that always throws (a network
/// failure at the seam).
class ThrowingUpdateCheckClient implements UpdateCheckClient {
  @override
  Future<UpdateInfo?> fetchLatestRelease() async =>
      throw StateError('network down (test)');
}

void main() {
  late FakeUpdateCheckClient client;
  late FakeAppVersionReader versionReader;
  late FakeUrlOpener urlOpener;
  late InMemoryUpdateStateRepository repository;
  late FakeUpdateClock clock;
  late bool recording;
  late ProviderContainer container;

  UpdateCheckState state() => container.read(updateCheckControllerProvider);

  UpdateCheckController controller() =>
      container.read(updateCheckControllerProvider.notifier);

  /// A release of [version] on GitHub (the pinned repo's release page).
  UpdateInfo release(String version) => UpdateInfo(
        version: version,
        releasePageUrl: Uri.parse(
            'https://github.com/Hendriksie/VoxGale/releases/tag/v$version'),
      );

  /// The controller's epoch-ms timestamp for the fake clock's current time.
  int nowMs() => clock.now().millisecondsSinceEpoch;

  ProviderContainer createContainer({
    UpdateCheckClient? checkClient,
    UpdateStateRepository? stateRepository,
  }) =>
      ProviderContainer(overrides: [
        updateCheckControllerProvider.overrideWith(() => UpdateCheckController(
              client: checkClient ?? client,
              versionReader: versionReader,
              urlOpener: urlOpener,
              stateRepository: stateRepository ?? repository,
              clock: clock,
              isRecording: () => recording,
            )),
      ]);

  setUp(() {
    client = FakeUpdateCheckClient();
    versionReader = FakeAppVersionReader('1.2.0');
    urlOpener = FakeUrlOpener();
    repository = InMemoryUpdateStateRepository();
    clock = FakeUpdateClock();
    recording = false;
    container = createContainer();
  });

  tearDown(() => container.dispose());

  group('UpdateCheckState', () {
    test('defaults to an idle, empty state', () {
      const state = UpdateCheckState();
      expect(state.checking, isFalse);
      expect(state.outcome, isNull);
      expect(state.available, isNull);
      expect(state.installedVersion, isNull);
      expect(state.errorMessage, isNull);
      expect(state.hasUpdate, isFalse);
    });

    test('copyWith keeps omitted fields and clears explicit nulls', () {
      final info = UpdateInfo(
        version: '1.3.0',
        releasePageUrl: Uri.parse('https://example.com/v1.3.0'),
      );
      final full = UpdateCheckState(
        checking: true,
        outcome: UpdateCheckOutcome.failed,
        available: info,
        installedVersion: '1.2.0',
        errorMessage: 'failed',
      );
      expect(full.copyWith(checking: false), full.copyWith(checking: false));
      expect(
        full.copyWith(checking: false),
        isNot(full),
      );
      // Omitted nullable fields keep their values.
      expect(full.copyWith(checking: false).available, info);
      expect(full.copyWith(checking: false).outcome,
          UpdateCheckOutcome.failed);
      // Explicit nulls clear the nullable fields.
      final cleared = full.copyWith(available: null, errorMessage: null);
      expect(cleared.available, isNull);
      expect(cleared.errorMessage, isNull);
      expect(cleared.installedVersion, '1.2.0');
      expect(cleared.hasUpdate, isFalse);
    });

    test('states with the same content are equal', () {
      final info = UpdateInfo(
        version: '1.3.0',
        releasePageUrl: Uri.parse('https://example.com/v1.3.0'),
      );
      expect(
        const UpdateCheckState(installedVersion: '1.2.0'),
        const UpdateCheckState(installedVersion: '1.2.0'),
      );
      expect(
        UpdateCheckState(available: info).hashCode,
        UpdateCheckState(available: info).hashCode,
      );
      expect(
        const UpdateCheckState(installedVersion: '1.2.0'),
        isNot(const UpdateCheckState(installedVersion: '1.2.1')),
      );
    });
  });

  group('checkOnStart', () {
    test('makes no request within the 24-hour throttle window', () async {
      repository.stored = StoredUpdateState(lastCheckAtMs: nowMs());
      client.result = release('1.3.0');

      await controller().checkOnStart();

      expect(client.callCount, 0);
      expect(state().available, isNull);
      expect(repository.stored.lastCheckAtMs, nowMs());
    });

    test('makes a request once the throttle window has passed', () async {
      repository.stored = StoredUpdateState(
        lastCheckAtMs: nowMs() - UpdateConfig.checkThrottle.inMilliseconds,
      );
      client.result = release('1.3.0');

      await controller().checkOnStart();

      expect(client.callCount, 1);
      expect(state().available, release('1.3.0'));
    });

    test('advances the persisted time on a well-formed response and '
        'throttles the next start', () async {
      client.result = release('1.3.0');

      await controller().checkOnStart();

      expect(repository.stored.lastCheckAtMs, nowMs());
      expect(repository.stored.lastNotifiedVersion, isNull);
      // The next start within the window makes no request.
      await controller().checkOnStart();
      expect(client.callCount, 1);
    });

    test('does not advance the persisted time when the check fails, '
        'retrying on the next start', () async {
      client.result = null; // network / API / malformed response

      await controller().checkOnStart();

      expect(client.callCount, 1);
      expect(repository.stored.lastCheckAtMs, isNull);
      expect(state().available, isNull);
      // The next start retries (no throttle without a well-formed check).
      client.result = release('1.3.0');
      await controller().checkOnStart();
      expect(client.callCount, 2);
      expect(state().available, release('1.3.0'));
    });

    test('publishes a newer, unnotified version when not recording', () async {
      client.result = release('1.3.0');

      await controller().checkOnStart();

      expect(state().available, release('1.3.0'));
      expect(state().installedVersion, '1.2.0');
      expect(state().hasUpdate, isTrue);
      // The automatic check reports no manual-check outcome.
      expect(state().outcome, isNull);
      expect(state().checking, isFalse);
    });

    test('does not publish a version that was already notified', () async {
      repository.stored = const StoredUpdateState(
        lastCheckAtMs: 0,
        lastNotifiedVersion: '1.3.0',
      );
      client.result = release('1.3.0');

      await controller().checkOnStart();

      expect(state().available, isNull);
      // A well-formed response still advances the persisted time.
      expect(repository.stored.lastCheckAtMs, nowMs());
      expect(repository.stored.lastNotifiedVersion, '1.3.0');
    });

    test('suppresses the dialog while recording without marking the '
        'version notified', () async {
      recording = true;
      client.result = release('1.3.0');

      await controller().checkOnStart();

      expect(state().available, isNull);
      expect(repository.stored.lastNotifiedVersion, isNull);
      // A later app start (past the throttle window, no longer
      // recording) shows it.
      recording = false;
      clock.advance(const Duration(hours: 25));
      await controller().checkOnStart();
      expect(state().available, release('1.3.0'));
    });

    test('does not publish the same or an older version', () async {
      client.result = release('1.2.0'); // same as installed
      await controller().checkOnStart();
      expect(state().available, isNull);

      clock.advance(const Duration(hours: 25));
      client.result = release('1.1.0'); // older than installed
      await controller().checkOnStart();
      expect(state().available, isNull);
      // Both responses were well-formed: the time advanced both times.
      expect(repository.stored.lastCheckAtMs, nowMs());
    });

    test('does not publish a version that is not a semantic version',
        () async {
      client.result = release('nightly');

      await controller().checkOnStart();

      expect(state().available, isNull);
      expect(repository.stored.lastCheckAtMs, nowMs());
    });

    test('fails silently when storage fails', () async {
      container.dispose();
      container = createContainer(stateRepository: ThrowingUpdateStateRepository());
      client.result = release('1.3.0');

      await controller().checkOnStart(); // must not throw

      expect(state().available, isNull);
      expect(state().outcome, isNull);
    });
  });

  group('checkNow', () {
    test('bypasses the 24-hour throttle', () async {
      repository.stored = StoredUpdateState(lastCheckAtMs: nowMs());
      client.result = release('1.3.0');

      await controller().checkNow();

      expect(client.callCount, 1);
      expect(state().outcome, UpdateCheckOutcome.updateAvailable);
      expect(state().available, release('1.3.0'));
      expect(state().installedVersion, '1.2.0');
      expect(state().checking, isFalse);
      // A well-formed response advances the persisted time.
      expect(repository.stored.lastCheckAtMs, nowMs());
    });

    test('reports updateAvailable even when already notified and while '
        'recording', () async {
      repository.stored = const StoredUpdateState(
        lastNotifiedVersion: '1.3.0',
      );
      recording = true;
      client.result = release('1.3.0');

      await controller().checkNow();

      expect(state().outcome, UpdateCheckOutcome.updateAvailable);
      expect(state().available, release('1.3.0'));
      expect(state().installedVersion, '1.2.0');
      // The manual check does not mark the version notified itself.
      expect(repository.stored.lastNotifiedVersion, '1.3.0');
    });

    test('reports upToDate when the installed version is current', () async {
      client.result = release('1.2.0');

      await controller().checkNow();

      expect(state().outcome, UpdateCheckOutcome.upToDate);
      expect(state().available, isNull);
      expect(state().installedVersion, '1.2.0');
      expect(state().checking, isFalse);
      expect(repository.stored.lastCheckAtMs, nowMs());
    });

    test('reports failed with a message when the check fails, without '
        'advancing the time', () async {
      client.result = null;

      await controller().checkNow();

      expect(state().outcome, UpdateCheckOutcome.failed);
      expect(state().errorMessage,
          UpdateCheckController.checkFailedMessage);
      expect(state().checking, isFalse);
      expect(state().available, isNull);
      expect(repository.stored.lastCheckAtMs, isNull);
    });

    test('reports failed when the client throws', () async {
      container.dispose();
      container = createContainer(checkClient: ThrowingUpdateCheckClient());

      await controller().checkNow();

      expect(state().outcome, UpdateCheckOutcome.failed);
      expect(state().errorMessage, contains('network down (test)'));
      expect(state().checking, isFalse);
      expect(repository.stored.lastCheckAtMs, isNull);
    });

    test('sets checking while a check is in flight and ignores a second '
        'checkNow', () async {
      final gated = GatedUpdateCheckClient();
      container.dispose();
      container = createContainer(checkClient: gated);

      final first = controller().checkNow();
      expect(state().checking, isTrue);
      expect(state().outcome, isNull);

      // A second tap while the check runs is a no-op.
      final second = controller().checkNow();
      expect(gated.callCount, 1);

      gated.complete(release('1.3.0'));
      await first;
      await second;

      expect(gated.callCount, 1);
      expect(state().checking, isFalse);
      expect(state().outcome, UpdateCheckOutcome.updateAvailable);
      expect(state().available, release('1.3.0'));
    });

    test('clears a previous outcome and message when a new check starts',
        () async {
      client.result = null;
      await controller().checkNow();
      expect(state().outcome, UpdateCheckOutcome.failed);
      expect(state().errorMessage, isNotNull);

      client.result = release('1.2.0');
      await controller().checkNow();

      expect(state().outcome, UpdateCheckOutcome.upToDate);
      expect(state().errorMessage, isNull);
    });
  });

  group('dialog actions', () {
    test('dismissUpdate records the version as notified and clears '
        'available', () async {
      client.result = release('1.3.0');
      await controller().checkOnStart();
      expect(state().available, release('1.3.0'));
      final checkedAtMs = repository.stored.lastCheckAtMs;

      await controller().dismissUpdate();

      expect(state().available, isNull);
      expect(state().hasUpdate, isFalse);
      expect(repository.stored.lastNotifiedVersion, '1.3.0');
      // The last-check time is merged, not clobbered.
      expect(repository.stored.lastCheckAtMs, checkedAtMs);
      // A later start does not show the dialog again for that version.
      clock.advance(const Duration(hours: 25));
      await controller().checkOnStart();
      expect(state().available, isNull);
    });

    test('openRelease opens the release page and records the version as '
        'notified', () async {
      client.result = release('1.3.0');
      await controller().checkOnStart();
      expect(state().available, release('1.3.0'));

      await controller().openRelease();

      expect(urlOpener.openedUrls, [release('1.3.0').releasePageUrl]);
      expect(state().available, isNull);
      expect(repository.stored.lastNotifiedVersion, '1.3.0');
    });

    test('dismissUpdate and openRelease are no-ops without a published '
        'update', () async {
      await controller().dismissUpdate();
      await controller().openRelease();

      expect(urlOpener.openedUrls, isEmpty);
      expect(repository.stored, const StoredUpdateState());
      expect(state(), const UpdateCheckState());
    });
  });
}
