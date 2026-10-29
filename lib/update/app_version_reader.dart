// The installed-version seam (change 2026-10-29-update-tracker, design
// decisions 3, 11): the interface the update layer calls to learn the
// installed app's version, and the package_info_plus production
// implementation. pubspec.yaml's `version:` flows into the platform
// package info (the Android versionName) at build time, so there is no
// second version constant to drift. The seam exists because platform
// channels throw or hang in widget tests (project gotcha) — tests use
// FakeAppVersionReader from test/update/fakes.dart instead.

import 'package:package_info_plus/package_info_plus.dart';

/// Reads the installed app's version (design decision 3).
abstract interface class AppVersionReader {
  /// The installed app's versionName as a bare semantic version
  /// (`'1.2.0'`), injected from pubspec.yaml at build time.
  Future<String> readVersionName();
}

/// [AppVersionReader] over package_info_plus's platform channel.
class PackageInfoAppVersionReader implements AppVersionReader {
  @override
  Future<String> readVersionName() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }
}
