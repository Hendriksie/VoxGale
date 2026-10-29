// The URL-opener seam (change 2026-10-29-update-tracker, design decisions
// 4, 11): the interface the update dialog's primary action calls to open
// the release page, and the url_launcher production implementation. The
// release page is an http(s) URL, so LaunchMode.externalApplication opens
// it in the device's browser (share_plus only shares content — design
// decision 4 rejected it). The seam exists because platform channels
// throw or hang in widget tests (project gotcha) — tests use FakeUrlOpener
// from test/update/fakes.dart instead.

import 'package:url_launcher/url_launcher.dart';

/// Opens a URL outside the app (design decision 4).
abstract interface class UrlOpener {
  /// Opens [url] in the device's browser. False when no browser can open
  /// it — the app does not crash and the dialog remains usable (spec:
  /// "Open the release page in the browser").
  Future<bool> open(Uri url);
}

/// [UrlOpener] over url_launcher's platform channel.
class UrlLauncherUrlOpener implements UrlOpener {
  @override
  Future<bool> open(Uri url) async {
    try {
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      // url_launcher returns false or throws a PlatformException depending
      // on the failure; the seam's contract is a plain bool either way.
      return false;
    }
  }
}
