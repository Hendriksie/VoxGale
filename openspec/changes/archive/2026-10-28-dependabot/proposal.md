# Proposal

## Why

The repository is about to go public. Two dependency surfaces drift over
time and nobody watches them: the Dart/Flutter packages in
`pubspec.yaml` (pub.dev) and the GitHub Actions versions in
`.github/workflows/*.yml` (`actions/checkout@v6`, `actions/setup-java@v5`
are major tags that move under us — the release workflow's header already
records that a third-party Flutter action disappeared once and broke
action resolution). Dependabot supports both ecosystems natively, and
vulnerability alerts for them are a free repository setting. Why now:
the go-public change is still open and this is the natural moment to
switch on dependency hygiene before the first outside eyes arrive.

## What Changes

- Add `.github/dependabot.yml` with two weekly update jobs:
  - `pub` (directory `/`) — Dart/Flutter dependencies from pub.dev.
  - `github-actions` (directory `/`) — action versions in the workflows.
  Both capped at `open-pull-requests-limit: 5` to keep PR noise low for a
  solo project.
- **User steps in the GitHub UI** (not configurable in `dependabot.yml`):
  enable **Dependabot alerts** (Settings → Security & analysis) so
  vulnerabilities in the pub dependency graph surface on the Security
  tab, and optionally **Dependabot security updates** for automatic fix
  PRs.

No spec changes: this is pure repository tooling (`skip_specs: true`).

## Capabilities

None — no spec-level behavior changes (pure tooling). `skip_specs: true`
is set in `.openspec.yaml`.

## Impact

- **New file**: `.github/dependabot.yml`.
- **No code or dependency changes** to the app itself; the pub job only
  opens PRs that bump `pubspec.yaml`/`pubspec.lock`, which still have to
  pass `flutter analyze` + `flutter test` in CI before merge.
- **User steps**: enable Dependabot alerts (+ optionally security
  updates) in the repository settings. Note: CodeQL/dependency-scanning
  code analysis has no Dart extractor, so the alerts come from the
  dependency graph (pub is supported), not from CodeQL.
