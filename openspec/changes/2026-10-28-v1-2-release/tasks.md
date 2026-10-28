# Tasks

## 1. Version bump + changelog

- [x] 1.1 Bump `pubspec.yaml` version `1.1.0+2` → `1.2.0+3`. (Verified: version line updated.)
- [x] 1.2 Add the `## [v1.2.0] - 2026-10-28` section to `CHANGELOG.md` (Changed: new launcher icon — speech bubble with waveform). (Verified: section added.)
- [x] 1.3 Validate: `openspec validate 2026-10-28-v1-2-release --strict`; `flutter analyze` clean; the awk changelog extraction returns the new section for tag `v1.2.0`. (Verified: change valid; analyze — no issues; extraction returns the section.)

## 2. Cut the release

- [ ] 2.1 Commit and push master.
- [ ] 2.2 Tag `v1.2.0` and push the tag — the release workflow runs (analyze + test + signed APK + publish).
- [ ] 2.3 Verify the published release: APK asset `voxgale-v1.2.0.apk` attached, signature verified by the workflow, and the release notes match the CHANGELOG section (first live test of the changelog-driven notes).

## 3. Wrap up

- [ ] 3.1 Archive the change after the release verifies (`openspec archive`), then `openspec validate --specs --strict`.
