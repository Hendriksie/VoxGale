# Proposal

## Why

VoxGale v1.1.0 is shipped (signed APKs on GitHub Releases) and the repository
is still private. The user wants to open the repository to the public. An
audit of the repository found it is already clean of secrets and debug
surface, but it is missing the files and conventions a public open-source
repository needs: no license, no changelog, one-line release notes, the
completed v1 `project-plan.md` still at the root, no contributing guide, no
CI, and no place to park future ideas now that plans go through OpenSpec.
Why now: the app is stable enough to be shown, and the go-public work is
small enough to do in one pass before flipping the visibility switch.

## What Changes

- **License**: add `LICENSE` (MIT, user decision 2026-10-28). Without a
  license the repository is "all rights reserved" and the F-Droid route in
  the distribution plan stays closed.
- **Changelog**: add `CHANGELOG.md` in Keep a Changelog format, with an
  `## [Unreleased]` section and one section per released tag (`v1.0.0`,
  `v1.1.0`), written from the archived OpenSpec proposals.
- **Release notes**: the existing `v1.0.0` and `v1.1.0` GitHub Releases
  currently carry one-line notes; draft proper notes (matching the
  CHANGELOG sections) under `docs/release-notes/` for the user to paste in
  the GitHub UI — this environment has no `gh` CLI/token and the GitHub MCP
  is read-only for releases. The release workflow
  (`.github/workflows/release.yml`) learns to generate release notes from
  the matching CHANGELOG section for all future tags.
- **Repository hygiene**: move the completed `project-plan.md` to
  `docs/project-plan.md` as the historical v1 record (all phases are
  checked off; OpenSpec is the planning flow now) and fix the two links
  that point at it (`README.md`, `docs/friction-list.md`).
- **Ideas parking lot**: add `docs/ideas.md`, seeded with the future
  ideas from `project-plan.md` §9, the open dogfood observation in
  `docs/friction-list.md`, and the cancelled Phase-0 spike questions.
  Ideas mature into OpenSpec proposals from there.
- **Open-source boilerplate**: add `CONTRIBUTING.md` (OpenSpec proposal
  flow, issues for bugs, no live API in tests), `SECURITY.md` (private
  vulnerability reporting), and a bug-report issue template under
  `.github/ISSUE_TEMPLATE/`.
- **CI**: add `.github/workflows/ci.yml` running `flutter analyze` and
  `flutter test` on pushes and pull requests (today only the tag-triggered
  release workflow runs). First-party Flutter setup, mirroring
  `release.yml`.
- **README**: update the Development section to link the changelog, the
  contributing guide, the ideas parking lot, and the archived plan; the
  screenshots/header-banner section is added once the presentation assets
  exist (task group 6).
- **Icon redesign**: generate 2–3 launcher-icon redesign options, present
  them to the user, and apply the chosen one at every Android density
  (`mipmap-*`) and as the adaptive-icon foreground vector, replacing the
  v1.0 waveform glyph.
- **Repository presentation assets** (after the icon is chosen): a README
  header image and a 1280×640 GitHub social-preview image derived from the
  final icon, plus app screenshots (device capture) wired into the README.

Not in this change: flipping the repository to public and the GitHub
settings (description, topics, social preview, Discussions) — those are
one-time user steps in the GitHub UI, listed in tasks.md. No new Dart
dependencies; no app behavior changes except the launcher icon.

## Capabilities

### New Capabilities

- `oss-readiness`: the repository carries the files and conventions of a
  public open-source project — MIT license, Keep a Changelog changelog,
  contributing/security/issue-template boilerplate, a CI gate on
  analyze + test, an ideas parking lot at `docs/ideas.md`, and the
  historical project plan archived under `docs/` with working links.

### Modified Capabilities

- `release-distribution`: release notes are generated from the CHANGELOG
  section for the pushed tag (with a one-line fallback), instead of a
  fixed sentence.
- `app-icon`: the launcher icon is redesigned (maintainer picks one of the
  presented options) and applied at every density and as the adaptive-icon
  foreground, replacing the v1.0 waveform glyph.

## Impact

- **New files**: `LICENSE`, `CHANGELOG.md`, `CONTRIBUTING.md`,
  `SECURITY.md`, `docs/ideas.md`, `docs/release-notes/v1.0.0.md`,
  `docs/release-notes/v1.1.0.md`, `.github/ISSUE_TEMPLATE/bug_report.md`,
  `.github/workflows/ci.yml`; `project-plan.md` moves to
  `docs/project-plan.md`.
- **Changed files**: `.github/workflows/release.yml` (changelog-driven
  notes), `README.md` (Development links), `docs/friction-list.md` (plan
  link), `android/app/src/main/res/mipmap-*/ic_launcher.png` +
  `drawable/ic_launcher_foreground.xml` (icon, after the user picks).
- **No new dependencies**: no pubspec changes; the CI workflow reuses the
  first-party Flutter setup pattern from `release.yml`.
- **No app behavior changes** except the launcher icon; no release is cut
  in this change (the next `v*` tag picks the new icon up).
- **User steps outside the repo** (GitHub UI): paste the drafted release
  notes, set description/topics, upload the social preview, optionally
  enable Discussions, flip the repository to public.
