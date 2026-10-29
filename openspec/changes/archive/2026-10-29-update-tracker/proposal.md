# Proposal

## Why

VoxGale ships as sideloaded APKs from GitHub Releases, so users get no
in-app signal that a newer release exists — they only learn about updates
by visiting the repository or hearing about them. The parking-lot idea
"In-app update check" (`docs/ideas.md`, 2026-10-28) captures this, but it
also bundles a full in-app updater (download + install flow, signature
verification), which is a bigger change. This change extracts the useful
piece from that idea: an automatic update tracker that tells the user a
new version is available and opens the right GitHub release, plus a
manual "Check for updates" action in Settings.

## What Changes

- New `update-tracker` capability: on app start (throttled to at most one
  network check per 24 hours per install), query the GitHub Releases API
  for the latest release of `Hendriksie/VoxGale`, compare its `v<semver>`
  tag against the installed app version, and — when a newer version exists
  and has not been notified yet — show a dialog naming both versions whose
  primary action opens that release's GitHub page in the browser.
- A manual "Check for updates" action in a new Updates section of the
  settings screen: an immediate check (bypassing the throttle) that shows
  the same update dialog when a newer version exists, an up-to-date
  confirmation otherwise, and the settings screen's existing error banner
  (with retry) when the check fails.
- New `lib/update/` layer (client interface + dio implementation, app
  version reader, URL opener — all behind seams so tests never touch
  platform channels), Riverpod wiring, a Drift table for the check state
  (schema v2 → v3), and the dialog shown from the home screen.
- Two new dependencies (justified under Impact); dio is reused.
- `CHANGELOG.md` gains an `## [Unreleased]` Added entry; `PRIVACY.md`
  gains one transparency sentence about the anonymous update check;
  `docs/ideas.md` marks the idea as promoted except for the in-app
  updater (tracker and manual check done, updater still parked).
- Explicitly NOT in this change: the in-app updater (download + install
  flow, signature verification of downloaded artifacts, full vs delta
  APKs). It stays in `docs/ideas.md` for a follow-up change.

## Capabilities

### New Capabilities

- `update-tracker`: automatic and manual update checks against GitHub
  Releases, with a popup that opens the release page.

### Modified Capabilities

- None. `release-distribution` is unchanged (GitHub Releases stays the
  version source of truth; the tracker only reads it). `settings` is
  unchanged at the requirement level — the settings screen gains an
  Updates section, but its spec lists what the screen must show, not an
  exhaustive list, and no requirement text changes. `privacy-policy` is
  unchanged at the requirement level — the check sends no user data and
  is not analytics/telemetry — but `PRIVACY.md` gains one sentence naming
  the check, which is a docs update, not a requirement change.

## Impact

- Code: new `lib/update/` (`UpdateCheckClient` interface,
  `DioUpdateCheckClient`, `AppVersionReader`, `UrlOpener` seams,
  `UpdateInfo` model), Riverpod providers for the check, an
  `update_state` table in `lib/storage/app_database.dart` (schemaVersion
  2 → 3 with migration) plus a small repository, the update dialog
  widget presented from the home screen, and an Updates section with a
  check button on the settings screen.
- Dependencies (new, one-line justification each):
  - `package_info_plus` — no existing dependency exposes the installed
    app's versionName; pubspec.yaml's `version:` flows into the platform
    package info at build time.
  - `url_launcher` — no existing dependency can open an external URL in
    the device browser (share_plus only shares content).
  - `dio` is reused (already a dependency) for the GitHub API call, with
    explicit connect/receive timeouts (dio has no defaults).
- Network: unauthenticated `GET
  https://api.github.com/repos/Hendriksie/VoxGale/releases/latest`, at
  most once per 24 hours per install. The `INTERNET` permission is
  already declared. No API key, credential, or user data is sent — the
  settings spec's rule that the key goes only to `api.mistral.ai` holds.
- Tests: mocktail unit tests for the semver comparison and the client
  (mocked dio — tests never hit the live GitHub API, same rule as the
  Mistral API), an in-memory Drift storage test, and a widget test with
  injected fakes (package_info_plus and url_launcher are platform
  channels, so they sit behind the seams).
- Docs: `CHANGELOG.md`, `PRIVACY.md`, `docs/ideas.md`.
