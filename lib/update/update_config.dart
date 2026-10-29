// Pinned constants for the update tracker (change 2026-10-29-update-tracker,
// design decisions 1-2, 7): the GitHub repository whose Releases are the
// version source of truth (release-distribution spec: releases are published
// on `v*` tags), the unauthenticated endpoint reporting the latest release,
// the `v`-prefixed semantic-version tag scheme, and the automatic check
// throttle.

class UpdateConfig {
  UpdateConfig._();

  /// The GitHub repository whose Releases are the version source of truth.
  static const String githubOwner = 'Hendriksie';

  /// The GitHub repository whose Releases are the version source of truth.
  static const String githubRepo = 'VoxGale';

  /// Host of the GitHub REST API (unauthenticated, public repo).
  static final Uri apiHostUri = Uri(scheme: 'https', host: 'api.github.com');

  /// API path reporting the latest published release of the repository.
  static const String latestReleasePath =
      '/repos/$githubOwner/$githubRepo/releases/latest';

  /// Release tags are `v`-prefixed semantic versions (`v1.2.0`).
  static const String tagPrefix = 'v';

  /// At most one automatic check per 24 hours per install (the manual
  /// "Check for updates" action bypasses this — design decision 15).
  static const Duration checkThrottle = Duration(hours: 24);
}
