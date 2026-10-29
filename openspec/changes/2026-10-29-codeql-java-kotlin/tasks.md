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
- [ ] 4.2 Commit and push; the push triggers the new CodeQL workflow on
  `master` — watch it go green end-to-end (the real proof that autobuild
  is replaced by the manual build).

## Workflow follow-up

- Review with the user; archive after the change is reviewed and the
  first CodeQL run is green.
- If the user also enabled the paid **Code Quality** feature (Settings →
  Security → Code quality), add `analysis-kinds: code-scanning,code-quality`
  to the `init` step — the default-setup matrix evidence (`actions`
  language present) suggests code scanning was enabled, which this
  workflow runs.
