// The update dialog (change 2026-10-29-update-tracker, tasks 6.1-6.2,
// design decisions 8, 10, 16): the Material 3 popup shown when an update
// check finds a newer release. The home screen presents it from the
// update check controller's state (design decision 10), and the settings
// screen's manual check reports through the same dialog (design
// decision 16). The dialog names both versions; its two actions both
// record the version as notified (design decision 8) — "Later" dismisses,
// "Open release" opens the release page in the browser and dismisses. It
// is not barrier-dismissable, so the only ways out are the two actions
// (spec: "Show the update dialog once per version"). It is presented on
// the root navigator so it also covers pushed routes (the settings
// screen's manual check). The primary action's orange styling mirrors
// the settings screen's "Save key" button.

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/theme.dart';
import 'update_check_client.dart';
import 'update_check_controller.dart';

/// Shows the update dialog for [info] — the available release — naming the
/// installed version [installedVersion] (the controller publishes
/// [UpdateCheckState.available] together with the installed version, so it
/// is set whenever the dialog is shown).
///
/// Both actions dismiss the dialog and record the version as notified
/// through [controller]: "Later" calls [UpdateCheckController.dismissUpdate],
/// "Open release" calls [UpdateCheckController.openRelease] (which opens
/// the release page through the [UrlOpener] seam — a URL that cannot be
/// opened neither crashes the app nor blocks the dismissal).
Future<void> showUpdateDialog(
  BuildContext context, {
  required UpdateCheckController controller,
  required UpdateInfo info,
  required String? installedVersion,
}) {
  return showDialog<void>(
    context: context,
    // Over any pushed route (the settings screen's manual check).
    useRootNavigator: true,
    // The only ways out are the two actions.
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Update available'),
      content: Text(
        'VoxGale v${info.version} is available '
        '(you have v$installedVersion).',
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            unawaited(controller.dismissUpdate());
          },
          child: const Text('Later'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: mistralOrange,
            foregroundColor: Colors.black,
          ),
          onPressed: () {
            Navigator.of(dialogContext).pop();
            unawaited(controller.openRelease());
          },
          child: const Text('Open release'),
        ),
      ],
    ),
  );
}
