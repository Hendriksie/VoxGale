// The update check client seam, the `UpdateInfo` model, and the pure
// semver helpers (change 2026-10-29-update-tracker, design decisions 1-2):
// the interface the update layer calls to learn the latest GitHub release,
// and the tag/version parsing and comparison that decide whether that
// release is newer than the installed app. The helpers are pure functions
// so the comparison logic is unit-testable without the network. The tag
// scheme (`v`-prefixed semantic versions) is pinned in `UpdateConfig`.

import 'update_config.dart';

/// The latest published release, as reported by the GitHub Releases API.
class UpdateInfo {
  const UpdateInfo({required this.version, required this.releasePageUrl});

  /// The release's version as a bare semantic version (`'1.3.0'`), with
  /// the `v` tag prefix stripped.
  final String version;

  /// The release's page on GitHub — the update dialog's primary action
  /// opens this URL in the device's browser.
  final Uri releasePageUrl;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UpdateInfo &&
          version == other.version &&
          releasePageUrl == other.releasePageUrl;

  @override
  int get hashCode => Object.hash(version, releasePageUrl);
}

/// Client for the GitHub Releases API (design decisions 1-2, 5).
abstract interface class UpdateCheckClient {
  /// Fetches the latest published release, or null when the API cannot be
  /// reached or the response is not a well-formed release — the automatic
  /// check fails silently (spec: "Check for a newer release on app start").
  Future<UpdateInfo?> fetchLatestRelease();
}

/// Parses a release tag into its three numeric components.
///
/// Only a `v`-prefixed `MAJOR.MINOR.PATCH` tag is accepted (the pinned tag
/// scheme, `UpdateConfig.tagPrefix`): exactly three dot-separated numeric
/// components. Anything else — `'nightly'`, `'v1.2'`, `'v1.2.3-beta'`,
/// `'1.2.3'` without the prefix — returns null, and the caller ignores the
/// release (spec: "Compare release versions semantically").
List<int>? parseVersionTag(String tag) {
  final prefix = UpdateConfig.tagPrefix;
  if (!tag.startsWith(prefix)) {
    return null;
  }
  return parseVersion(tag.substring(prefix.length));
}

/// Parses a bare semantic version (`'1.2.0'`, as reported for the
/// installed app's versionName) into its three numeric components.
///
/// Anything that is not exactly three dot-separated numeric components
/// returns null.
List<int>? parseVersion(String version) {
  final parts = version.split('.');
  if (parts.length != 3) {
    return null;
  }
  final components = <int>[];
  for (final part in parts) {
    // Digits only: rejects '', '1a', '-1', ' 1', and prerelease suffixes
    // ('3-beta' splits into '3-beta', which is not numeric). int.tryParse
    // also rejects components too large for an int.
    if (part.isEmpty || !RegExp(r'^[0-9]+$').hasMatch(part)) {
      return null;
    }
    final value = int.tryParse(part);
    if (value == null) {
      return null;
    }
    components.add(value);
  }
  return components;
}

/// Whether [candidate] is strictly newer than [installed], comparing the
/// three numeric components in order (major, then minor, then patch).
///
/// Equal versions are not newer, and malformed input on either side
/// returns false — a version that cannot be parsed never triggers an
/// update (spec: "Compare release versions semantically").
bool isNewerVersion(String candidate, String installed) {
  final candidateParts = parseVersion(candidate);
  final installedParts = parseVersion(installed);
  if (candidateParts == null || installedParts == null) {
    return false;
  }
  for (var i = 0; i < candidateParts.length; i++) {
    if (candidateParts[i] != installedParts[i]) {
      return candidateParts[i] > installedParts[i];
    }
  }
  return false;
}
