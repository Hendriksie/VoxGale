// Provider-level tests for the update tracker's Riverpod wiring (change
// 2026-10-29-update-tracker, task 5.2): the REAL provider graph in a
// ProviderContainer with only the seams overridden — the client, the
// version reader, and the URL opener go to the fakes in fakes.dart, and
// the app database goes to AppDatabase.memory() — so the controller's
// dependencies resolve through the graph exactly as in production. No
// test here hits the live GitHub API or a platform channel.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxgale/session/session_providers.dart';
import 'package:voxgale/storage/storage.dart';
import 'package:voxgale/update/update_check_client.dart';
import 'package:voxgale/update/update_check_controller.dart';
import 'package:voxgale/update/update_providers.dart';

import 'fakes.dart';

void main() {
  late FakeUpdateCheckClient client;
  late FakeUrlOpener urlOpener;
  late AppDatabase db;
  late ProviderContainer container;

  /// A release of [version] on GitHub (the pinned repo's release page).
  UpdateInfo release(String version) => UpdateInfo(
        version: version,
        releasePageUrl: Uri.parse(
            'https://github.com/Hendriksie/VoxGale/releases/tag/v$version'),
      );

  /// The real provider graph with only the seams overridden.
  ProviderContainer createContainer() => ProviderContainer(overrides: [
        updateCheckClientProvider.overrideWith((ref) => client),
        appVersionReaderProvider
            .overrideWith((ref) => FakeAppVersionReader('1.2.0')),
        urlOpenerProvider.overrideWith((ref) => urlOpener),
        appDatabaseProvider.overrideWith((ref) => db),
      ]);

  setUp(() {
    client = FakeUpdateCheckClient();
    urlOpener = FakeUrlOpener();
    db = AppDatabase.memory();
    container = createContainer();
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('the manual check runs through the real provider graph', () async {
    client.result = release('1.3.0');

    // The installed version comes from the overridden version reader.
    expect(await container.read(installedVersionProvider.future), '1.2.0');

    // checkNow drives the controller wired from the graph.
    final controller = container.read(updateCheckControllerProvider.notifier);
    await controller.checkNow();

    final state = container.read(updateCheckControllerProvider);
    expect(state.checking, isFalse);
    expect(state.outcome, UpdateCheckOutcome.updateAvailable);
    expect(state.available, release('1.3.0'));
    expect(state.installedVersion, '1.2.0');
    expect(state.errorMessage, isNull);

    // The real Drift repository (over AppDatabase.memory()) persisted the
    // well-formed check's time.
    final stored = await DriftUpdateStateRepository(db).loadUpdateState();
    expect(stored.lastCheckAtMs, isNotNull);
    expect(stored.lastNotifiedVersion, isNull);

    // The dialog's primary action opens the release page through the
    // overridden opener and records the version as notified in the real
    // repository.
    await controller.openRelease();
    expect(urlOpener.openedUrls, [release('1.3.0').releasePageUrl]);
    expect(container.read(updateCheckControllerProvider).available, isNull);
    expect(
      (await DriftUpdateStateRepository(db).loadUpdateState())
          .lastNotifiedVersion,
      '1.3.0',
    );

    // The start-check provider fires the throttled start check through
    // the graph: the manual check just advanced the persisted time, so
    // no second request is made within the window.
    await container.read(updateCheckOnStartProvider.future);
    expect(client.callCount, 1);
  });

  test('an up-to-date manual check reports through the real graph',
      () async {
    client.result = release('1.2.0'); // same as the fake installed version

    final controller = container.read(updateCheckControllerProvider.notifier);
    await controller.checkNow();

    final state = container.read(updateCheckControllerProvider);
    expect(state.outcome, UpdateCheckOutcome.upToDate);
    expect(state.available, isNull);
    expect(state.installedVersion, '1.2.0');
    expect(
      (await DriftUpdateStateRepository(db).loadUpdateState()).lastCheckAtMs,
      isNotNull,
    );
  });

  test('a failed manual check reports through the real graph', () async {
    client.result = null; // network / API / malformed response

    final controller = container.read(updateCheckControllerProvider.notifier);
    await controller.checkNow();

    final state = container.read(updateCheckControllerProvider);
    expect(state.outcome, UpdateCheckOutcome.failed);
    expect(state.errorMessage, isNotNull);
    expect(state.checking, isFalse);
    // A failed check does not advance the persisted time.
    expect(
      (await DriftUpdateStateRepository(db).loadUpdateState()).lastCheckAtMs,
      isNull,
    );
  });
}
