# Tasks

## 1. Reproduce and diagnose (done before writing the fix)

- [x] 1.1 Reproduce the autobuild failure in a clean checkout
  (`git worktree add --detach /tmp/opencode/voxgale-clean master`):
  a fresh checkout has no `android/gradlew` (gitignored) and no
  `android/local.properties` (gitignored); with a wrapper copied in,
  `./gradlew help` fails in ~2s at `settings.gradle.kts` line 5
  (`local.properties (No such file or directory)`). This is what CodeQL's
  java `autobuild.sh` hits on the runner — confirmed against the live
  run annotation ("We were unable to automatically build your code …
  autobuild.sh … Exit status 1").
- [x] 1.2 Confirm the remedy path: GitHub docs ("Automatic build failed
  for a compiled language") — default setup cannot express build steps;
  advanced setup with `build-mode: manual` is the documented fix.

## 2. CodeQL workflow (manual build)

- [x] 2.1 Add `.github/workflows/codeql.yml`: matrix `java-kotlin`
  (`build-mode: manual`) + `actions` (`build-mode: none`); pinned
  `ubuntu-24.04`; setup-java temurin 17, pinned Flutter 3.47.8 SDK and
  Android SDK steps copied verbatim from `release.yml`; `flutter pub get`
  + `flutter build apk --debug` between `codeql-action/init@v4` and
  `codeql-action/analyze@v4`; triggers push/PR to `master`, weekly
  schedule, `workflow_dispatch`. (Verified: file created.)
- [x] 2.2 Validate the YAML parses and the workflow structure is sound.
  (Verified: `python3 -c yaml.safe_load` parses; matrix/build-mode wiring
  matches the codeql-action `init` inputs.)

## 3. Verify the manual build from a clean checkout

- [x] 3.1 Run the workflow's exact build steps in the clean worktree
  (no `gradlew`, no `local.properties`):
  `flutter pub get && flutter build apk --debug`.
  (Verified: EXIT=0, `✓ Built build/app/outputs/flutter-apk/app-debug.apk`;
  the Flutter tool regenerated `android/gradlew` + `gradle-wrapper.jar`
  and wrote `android/local.properties` itself.)

## 4. Validation and rollout

- [x] 4.1 Run `openspec validate 2026-10-29-codeql-java-kotlin --strict`.
- [x] 4.2 Commit and push; the push triggers the new CodeQL workflow on
  `master`. (Verified 2026-10-29, run 40849762103: checkout, JDK 17,
  Flutter SDK, Android SDK, `flutter pub get`, `flutter build apk
  --debug`, CodeQL init, database creation and query execution all
  succeeded — the manual build works on the runner. The analyze step
  then failed ONLY at SARIF upload: "Code Scanning could not process the
  submitted SARIF file: CodeQL analyses from advanced configurations
  cannot be processed when the default setup is enabled". CI on the same
  commit is green.)

## 5. Repository settings (user steps)

- [x] 5.1 Switch CodeQL from default setup to advanced setup: Settings →
  Security and quality → CodeQL analysis → disable the default setup
  (java-kotlin / actions coverage is unchanged — the new workflow
  analyzes both). Until this is done, GitHub rejects the advanced
  workflow's SARIF upload (see 4.2). (Verified 2026-10-29: user disabled
  it; the re-run's SARIF was accepted.)
- [x] 5.2 Re-run the CodeQL workflow on `master` (Actions → CodeQL →
  "Run workflow", or push any commit) — it should go green end-to-end
  and the alerts appear under Security → Code scanning.
  (Verified 2026-10-29: run 40852631385 completed success.)

## 6. Warning triage

- [x] 6.1 The remaining init warning — "Cannot build an overlay-base
  database because build-mode is set to 'manual' instead of 'none'.
  Falling back to creating a normal full database instead." — is benign:
  it is CodeQL's improved incremental analysis (PR scans extracting only
  changed files via a no-build overlay-base database), which a manual
  build can't use. The full database is complete and correct; only the
  PR-scan speedup is lost, which is negligible here (the java-kotlin
  database is tiny; the Gradle build dominates). Not fixable while
  keeping a manual build (`none` is unsupported for Kotlin, `autobuild`
  is the original failure). Recorded in the KB Gotchas.

## Workflow follow-up

- Review with the user; archive after the change is reviewed (the
  workflow is green end-to-end).
- If the user also enabled the paid **Code Quality** feature (Settings →
  Security → Code quality), add `analysis-kinds: code-scanning,code-quality`
  to the `init` step — the default-setup matrix evidence (`actions`
  language present) suggests code scanning was enabled, which this
  workflow runs.
- Optional, if PR scan time ever matters: `dependency-caching: true` on
  the init step (advanced setup disables it by default) to cache the
  Gradle dependency downloads.
