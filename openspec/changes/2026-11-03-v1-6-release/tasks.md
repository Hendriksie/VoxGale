# Tasks

## 1. Version bump + changelog

- [x] 1.1 Bump `pubspec.yaml` version `1.5.0+6` → `1.6.0+7` (minor: post-session
  actions + dual-payload share since v1.5.0; build number increments the
  Android versionCode). Verify: `grep '^version' pubspec.yaml` shows
  `1.6.0+7`.
- [x] 1.2 Move the `## [Unreleased]` CHANGELOG content (Added: post-session
  Share/Send to agent on the live screen; Fixed: share offer carries
  `EXTRA_TEXT` at `text/plain` with the 500 KB size guard) under a new
  `## [v1.6.0] - 2026-11-03` section, leaving `## [Unreleased]` empty above
  it. Verify: the workflow's notes extraction for the tag returns the section —
  `awk -v tag="v1.6.0" 'index($0, "## [" tag "]") == 1 { found = 1; next }
  /^## / { if (found) exit } found { print }' CHANGELOG.md` prints the two
  entries.

## 2. Gates

- [x] 2.1 `flutter analyze` clean. Verify: "No issues found".
- [x] 2.2 `flutter test` all pass. Verify: "All tests passed".
- [x] 2.3 `openspec validate --strict 2026-11-03-v1-6-release` passes
  (`skip_specs: true`, no design.md — operational release step, no design
  decisions; see proposal). Verify: "Change ... is valid".

## 3. Commit + archive

- [ ] 3.1 Commit the release change (version bump, CHANGELOG section, this
  change's directory). Verify: `git log --oneline -1` shows the release
  commit and `git status --short` is clean.
- [ ] 3.2 Archive the change (`openspec archive 2026-11-03-v1-6-release --yes`),
  then `openspec validate --specs --strict` (14/14) and `openspec list --json`
  shows no active changes. Verify: archive output + validate totals.

## Workflow follow-up

- Push the commit and tag `v1.6.0` (`git push origin master && git tag v1.6.0
  && git push origin v1.6.0`) — from this machine if SSH auth works, otherwise
  a user step (no gh token here). The release workflow then runs analyze +
  test, builds the signed APK, and publishes the GitHub Release.
- Verify the published release: asset `voxgale-v1.6.0.apk` attached, signature
  verified by the workflow, and the release notes match the `## [v1.6.0]`
  CHANGELOG section.
