// Shared test doubles for the update-tracker tests (change
// 2026-10-29-update-tracker, tasks 4.2, 5.x, 6.x): fakes for the platform
// seams ([AppVersionReader], [UrlOpener]) and for the [UpdateCheckClient]
// — the controller and widget tests drive the update flow through these
// without touching platform channels or the network (design decision 11;
// platform channels throw or hang in widget tests — project gotcha).

import 'package:voxgale/update/app_version_reader.dart';
import 'package:voxgale/update/update_check_client.dart';
import 'package:voxgale/update/url_opener.dart';

/// In-memory [AppVersionReader] for tests: reports a fixed version string.
class FakeAppVersionReader implements AppVersionReader {
  FakeAppVersionReader(this.versionName);

  /// The installed version the fake reports.
  final String versionName;

  @override
  Future<String> readVersionName() async => versionName;
}

/// A [UrlOpener] test double: records the opened URLs and returns the
/// configured result.
class FakeUrlOpener implements UrlOpener {
  /// The URLs passed to [open], in order.
  final List<Uri> openedUrls = [];

  /// The result [open] returns.
  bool result = true;

  @override
  Future<bool> open(Uri url) async {
    openedUrls.add(url);
    return result;
  }
}

/// A [UpdateCheckClient] test double: returns a configurable [UpdateInfo]
/// (or a queue of them, one per call) and counts the calls.
class FakeUpdateCheckClient implements UpdateCheckClient {
  /// The result returned once [queue] is empty.
  UpdateInfo? result;

  /// Results returned in order, one per call, while non-empty (a test
  /// scripting a sequence — for example a failure, then a release).
  final List<UpdateInfo?> queue = [];

  /// How many times [fetchLatestRelease] was called.
  int callCount = 0;

  @override
  Future<UpdateInfo?> fetchLatestRelease() async {
    callCount++;
    if (queue.isNotEmpty) {
      return queue.removeAt(0);
    }
    return result;
  }
}
