// Widget tests for the update dialog (change 2026-10-29-update-tracker,
// tasks 6.1-6.2, design decisions 8-10 and 16): the home screen fires the
// throttled start check and presents the Material 3 update dialog when
// the check publishes a newer, un-notified version; both dialog actions
// dismiss it and record the version as notified; the dialog is suppressed
// when the installed version is current, when the version was already
// notified, and while a live session is recording; and the manual check
// shows it even when the version was already notified and while
// recording (explicit user intent). Everything runs through the fakes —
// no test here hits the live GitHub API or a platform channel.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxgale/app/live_session_screen.dart';
import 'package:voxgale/app/theme.dart';
import 'package:voxgale/session/live_session_controller.dart';
import 'package:voxgale/storage/storage.dart';
import 'package:voxgale/update/update_check_client.dart';
import 'package:voxgale/update/update_providers.dart';

import '../update/fakes.dart';
import 'fakes.dart';

void main() {
  late FakeUpdateCheckClient client;
  late FakeUrlOpener urlOpener;
  late InMemoryUpdateStateRepository updateState;
  late FakeAppVersionReader versionReader;

  /// A release of [version] on GitHub (the pinned repo's release page).
  UpdateInfo release(String version) => UpdateInfo(
        version: version,
        releasePageUrl: Uri.parse(
            'https://github.com/Hendriksie/VoxGale/releases/tag/v$version'),
      );

  setUp(() {
    client = FakeUpdateCheckClient();
    urlOpener = FakeUrlOpener();
    updateState = InMemoryUpdateStateRepository();
    versionReader = FakeAppVersionReader('1.2.0');
  });

  /// Pumps the home screen with the update fakes wired in.
  Future<void> pumpHome(
    WidgetTester tester, {
    LiveSessionState? sessionState,
  }) async {
    await tester.pumpWidget(appWithStore(
      FakeApiKeyStore(),
      sessionController: FakeLiveSessionController(sessionState),
      updateClient: client,
      updateStateRepository: updateState,
      urlOpener: urlOpener,
      appVersionReader: versionReader,
    ));
    await tester.pump();
  }

  /// The ProviderScope's container (to drive the update controller).
  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(LiveSessionScreen)));

  /// Awaits the start check the home screen fired on first build, then
  /// renders the result (the dialog route's transition included). Fixed
  /// pumps only — the recording indicator pulses forever while a session
  /// is active, so pumpAndSettle would never return.
  Future<void> settleStartCheck(WidgetTester tester) async {
    await containerOf(tester).read(updateCheckOnStartProvider.future);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// Renders the outcome of a state change the same way.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  group('update dialog (6.1)', () {
    testWidgets('the start check finding a newer, unnotified version shows '
        'the dialog naming both versions', (tester) async {
      client.result = release('1.3.0');
      await pumpHome(tester);
      await settleStartCheck(tester);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Update available'), findsOneWidget);
      expect(
        find.text('VoxGale v1.3.0 is available (you have v1.2.0).'),
        findsOneWidget,
      );
      expect(find.text('Later'), findsOneWidget);
      expect(find.text('Open release'), findsOneWidget);

      // The primary action mirrors the settings screen's "Save key"
      // button: Mistral orange with black text.
      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Open release'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.style?.backgroundColor?.resolve({}), mistralOrange);
      expect(button.style?.foregroundColor?.resolve({}), Colors.black);
    });

    testWidgets('"Later" dismisses the dialog, records the version as '
        'notified, and opens no URL', (tester) async {
      client.result = release('1.3.0');
      await pumpHome(tester);
      await settleStartCheck(tester);

      await tester.tap(find.text('Later'));
      await settle(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Update available'), findsNothing);
      // Dismissing by either action records the version as notified
      // (spec: "Show the update dialog once per version").
      expect(updateState.stored.lastNotifiedVersion, '1.3.0');
      expect(urlOpener.openedUrls, isEmpty);
    });

    testWidgets('"Open release" dismisses the dialog, opens the release '
        'page, and records the version as notified', (tester) async {
      client.result = release('1.3.0');
      await pumpHome(tester);
      await settleStartCheck(tester);

      await tester.tap(find.text('Open release'));
      await settle(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(urlOpener.openedUrls, [release('1.3.0').releasePageUrl]);
      expect(updateState.stored.lastNotifiedVersion, '1.3.0');
    });
  });

  group('suppression (6.2)', () {
    testWidgets('no dialog when the installed version is the latest',
        (tester) async {
      client.result = release('1.2.0'); // same as the fake installed version
      await pumpHome(tester);
      await settleStartCheck(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Update available'), findsNothing);
    });

    testWidgets('no dialog when the available version was already notified',
        (tester) async {
      updateState.stored = const StoredUpdateState(
        lastNotifiedVersion: '1.3.0',
      );
      client.result = release('1.3.0');
      await pumpHome(tester);
      await settleStartCheck(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Update available'), findsNothing);
    });

    testWidgets('no dialog while a session is recording — and the version '
        'is not recorded as notified', (tester) async {
      client.result = release('1.3.0');
      await pumpHome(
        tester,
        sessionState: const LiveSessionState(phase: LiveSessionPhase.active),
      );
      await settleStartCheck(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Update available'), findsNothing);
      // Suppressed, not notified: a later app start shows it (spec:
      // "Live session recording when the check completes").
      expect(updateState.stored.lastNotifiedVersion, isNull);
    });

    testWidgets('the manual check shows the dialog even when the version '
        'was already notified and while recording', (tester) async {
      updateState.stored = const StoredUpdateState(
        lastNotifiedVersion: '1.3.0',
      );
      client.result = release('1.3.0');
      await pumpHome(
        tester,
        sessionState: const LiveSessionState(phase: LiveSessionPhase.active),
      );
      // The automatic start check is suppressed (already notified and
      // recording).
      await settleStartCheck(tester);
      expect(find.byType(AlertDialog), findsNothing);

      // The manual check is explicit user intent: the dialog is shown
      // regardless (spec: "Report the outcome of a manual check").
      await containerOf(tester)
          .read(updateCheckControllerProvider.notifier)
          .checkNow();
      await settle(tester);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Update available'), findsOneWidget);
      expect(
        find.text('VoxGale v1.3.0 is available (you have v1.2.0).'),
        findsOneWidget,
      );
    });
  });
}
