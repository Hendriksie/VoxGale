# Proposal

## Why

The redesigned launcher icon (change `2026-10-28-go-public`, task 5.3)
landed on master but has not shipped — v1.1.0 predates it. The user asked
for a new release because the icon changed. The release workflow is proven
(v1.0.0, v1.1.0) and since the go-public change it also generates the
release notes from the CHANGELOG section for the pushed tag, so v1.2.0 is
the first release to exercise the changelog-driven notes end-to-end.

## What Changes

- Bump the app version in `pubspec.yaml`: `1.1.0+2` → `1.2.0+3` (minor —
  new launcher icon; the build number increments for the Android
  versionCode).
- Add the `## [v1.2.0] - 2026-10-28` section to `CHANGELOG.md`
  (Changed: new launcher icon).
- Push tag `v1.2.0` — the release workflow runs `flutter analyze` +
  `flutter test`, builds the signed release APK, verifies its signature,
  and publishes the GitHub Release with notes generated from the CHANGELOG
  section.
- Verify the published release: APK attached as `voxgale-v1.2.0.apk`, and
  the release notes match the CHANGELOG section (first live test of the
  changelog-driven notes).

No spec changes: cutting a release is covered by the existing
`release-distribution` spec (`skip_specs: true`).

## Capabilities

None — operational release step covered by the existing
`release-distribution` capability. `skip_specs: true` is set in
`.openspec.yaml`.

## Impact

- `pubspec.yaml` version line; `CHANGELOG.md` new section; tag `v1.2.0`; a
  new GitHub Release with the signed APK. No code changes — the workflow's
  analyze + test gate still runs on the tag.
