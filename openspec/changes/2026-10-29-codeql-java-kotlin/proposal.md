# Proposal

## Why

CodeQL was enabled for java/kotlin in the repository settings (Security and
quality → CodeQL, default setup). The first analysis run failed in the
autobuild step:

> We were unable to automatically build your code. Please replace the call
> to the autobuild action with your custom build steps. … A fatal error
> occurred: Exit status 1 from command: …/codeql/java/tools/autobuild.sh

Root cause (reproduced locally in a clean checkout of `master`):

1. `android/.gitignore` (Flutter template) ignores `gradlew`,
   `gradlew.bat`, and `gradle-wrapper.jar` — a fresh checkout has only
   `gradle/wrapper/gradle-wrapper.properties`, so CodeQL's Gradle
   autobuilder finds no wrapper to run.
2. Even with a wrapper, `android/settings.gradle.kts` requires
   `android/local.properties` with a `flutter.sdk` entry and
   `includeBuild`s `$flutterSdkPath/packages/flutter_tools/gradle`.
   `local.properties` is gitignored (machine-local), and the Flutter SDK
   must actually exist at that path. Reproduced: `./gradlew help` in a
   clean checkout fails in 2s at `settings.gradle.kts` line 5
   (`local.properties (No such file or directory)`).
3. The build also needs the Android SDK (compileSdk 36 / build-tools
   36.0.0, the NDK `flutter.ndkVersion` pins, CMake) and JDK 17 — none
   of which CodeQL's autobuild sets up.

Default setup cannot express build steps, so the fix is to switch this
language to advanced setup with a manual build (the documented remedy for
"automatic build failed").

## What Changes

- Add `.github/workflows/codeql.yml` (advanced setup for CodeQL), which
  replaces the settings-managed default setup for this repository:
  - Matrix keeps the languages default setup detected: `java-kotlin`
    (`build-mode: manual`) and `actions` (`build-mode: none`).
  - `java-kotlin` builds with the same first-party setup the release
    workflow already proves on GitHub runners: pinned Flutter SDK
    (3.47.8, extracted to `$HOME`, tarball deleted), pinned JDK 17
    (temurin), Android SDK into `$ANDROID_SDK_ROOT` (platforms;android-36,
    build-tools;36.0.0), then `flutter pub get` and
    `flutter build apk --debug` between `codeql-action/init` and
    `codeql-action/analyze` so the Gradle/Kotlin compilation is traced.
    The debug build needs no signing key, so no secrets are required.
  - Triggers: push/PR to `master`, weekly schedule, `workflow_dispatch`.
- No app code, dependency, or spec changes: pure repository tooling
  (`skip_specs: true`).

## Capabilities

None — no spec-level behavior changes (pure tooling). `skip_specs: true`
is set in `.openspec.yaml`.

## Impact

- **New file**: `.github/workflows/codeql.yml`.
- **User steps in the GitHub UI** (not expressible in the repo): switch
  CodeQL from default setup to advanced setup — Settings → Security and
  quality → CodeQL analysis → disable the default setup (the languages
  java-kotlin / actions stay covered by the new workflow). Until then,
  GitHub rejects the advanced workflow's SARIF upload with "Code Scanning
  could not process the submitted SARIF file: CodeQL analyses from
  advanced configurations cannot be processed when the default setup is
  enabled" (observed on the first run of the new workflow: the manual
  build and analysis completed, only the upload was rejected).
- **No code or dependency changes** to the app itself.
- The Flutter/Android setup steps are copied from `release.yml` (pinned
  runner `ubuntu-24.04`, pinned Flutter, first-party SDK installs) so CI
  and the analysis build cannot drift apart.
- Verification: the exact build commands
  (`flutter pub get` + `flutter build apk --debug`) were run in a clean
  `git worktree` of `master` (no `gradlew`, no `local.properties`) and
  completed successfully; the workflow then ran end-to-end on the push to
  `master` — setup, manual build, database creation and query execution
  all succeeded; only the SARIF upload was rejected because the default
  setup was still enabled (see user steps above). After the settings
  change, a re-run turns the check green.
- Follow-up risk (not blocking): if the CodeQL Kotlin extractor rejects
  Kotlin 2.4.0 as too new, extraction (not the build) would fail next;
  that would need a Kotlin or CodeQL version pin and is out of scope here.
