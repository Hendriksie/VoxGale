# Proposal

## Why

Two changes landed on master but have not shipped — v1.5.0 predates them:
`2026-11-01-post-session-actions` (Share / Send to agent on the live screen's
post-session card) and `2026-11-03-share-transcript-text-extra` (share offers
carry the export text in `EXTRA_TEXT` at `text/plain` alongside the file).
The user asked to wrap up and cut a new release, v1.6.0. The release workflow
is proven (v1.0.0–v1.5.0) and generates the release notes from the CHANGELOG
section for the pushed tag.

## What Changes

- Bump the app version in `pubspec.yaml`: `1.5.0+6` → `1.6.0+7` (minor — new
  post-session actions and the improved share payload; the build number
  increments for the Android versionCode).
- Move the `## [Unreleased]` CHANGELOG content (Added: post-session actions;
  Fixed: dual-payload share) under a new `## [v1.6.0] - 2026-11-03` section,
  leaving `## [Unreleased]` empty.
- Commit, then tag `v1.6.0` and push commit + tag — the release workflow runs
  `flutter analyze` + `flutter test`, builds the signed release APK, verifies
  its signature, and publishes the GitHub Release with notes extracted from
  the `## [v1.6.0]` CHANGELOG section.
- Verify the published release: APK attached as `voxgale-v1.6.0.apk`, release
  notes match the CHANGELOG section.

No spec changes: cutting a release is covered by the existing
`release-distribution` spec (`skip_specs: true`).

## Capabilities

None — operational release step covered by the existing
`release-distribution` capability. `skip_specs: true` is set in
`.openspec.yaml`.

## Impact

- `pubspec.yaml` version line; `CHANGELOG.md` new section; tag `v1.6.0`; a
  new GitHub Release with the signed APK. No code changes — the workflow's
  analyze + test gate still runs on the tag.
- Push/tag note: this machine has no gh token; the push and tag are done
  from the user's side if SSH auth is not available here (attempted first).
