# Tasks

## 1. Release signing (design P4-D1)

- [x] 1.1 Generate the release keystore at `android/app/upload-keystore.jks` with the local JDK 17's `keytool`, write `android/key.properties` (storeFile, keyAlias, storePassword, keyPassword), and back up both to the password manager / encrypted storage immediately; verify `git check-ignore android/key.properties android/app/upload-keystore.jks` reports both ignored and `git status` shows neither. (Keystore generated: RSA 2048, alias `upload`, 30-year validity; both files mode 600. USER ACTION REMAINS: back up the keystore + key.properties to the password manager — losing them means installed copies can never be updated.)
- [x] 1.2 Wire the release signing config in `android/app/build.gradle.kts`: load `key.properties`, configure `signingConfigs.release`, and replace the debug fallback with a `GradleException` naming the missing configuration when the file is absent; verify a release build fails with that message when `key.properties` is temporarily moved away and succeeds when restored. (Verified: release without key fails with the GradleException message; debug without key succeeds; release with key succeeds.)
- [x] 1.3 Verify the signed artifact: `flutter build apk --release`, then verify the APK's signature with `apksigner verify` against the release certificate; verify the APK carries versionName 1.0.0 / versionCode 1 from `pubspec.yaml`. (Verified: apksigner prints the release cert CN=Voxtral Live, O=Hendriksie, C=NL; badging shows versionCode='1' versionName='1.0.0'.)

## 2. Machine-independent Gradle config (design P4-D2)

- [ ] 2.1 Move `org.gradle.java.home` out of the committed `android/gradle.properties` into the user-level `~/.gradle/gradle.properties` (create it with the same JDK 17 path); verify a debug build still succeeds locally and `git diff` shows the line removed from the committed file.
- [ ] 2.2 Verify a clean checkout builds: `git worktree add` a fresh checkout to a temp directory and run `flutter build apk --debug` there (uses the user-level JDK pointer, not the committed file); verify the build succeeds and the worktree is removed afterwards.

## 3. Spike/debug harness removal (design P4-D3)

- [ ] 3.1 Delete `lib/spike/` (5 files), `lib/app/debug_hub_screen.dart`, `assets/spike/` (2 files), and `test/app/debug_hub_test.dart`; remove the debug route, app-bar action, and import from `lib/app/live_session_screen.dart`; remove the two spike asset entries from `pubspec.yaml`; verify `flutter analyze` is clean.
- [ ] 3.2 Move the still-valid home-screen assertions from the deleted debug-hub test (the live session screen is home, no spike links on home) into `test/app/live_session_screen_test.dart` if not already covered there; verify the full `flutter test` suite passes.
- [ ] 3.3 Verify the release artifact is clean: `flutter build apk --release`, `unzip -l` on the APK shows no `assets/spike/` entries, and the installed release app (device; uninstall the debug build first) shows no debug menu; verify with one live session and one file transcription on the release build (device smoke — emulators lie about background capture).

## 4. README and privacy policy (design P4-D4)

- [ ] 4.1 Rewrite `README.md`: what the app is, features, install (download the APK from Releases, allow "install unknown apps", uninstall any debug build first, first-launch key setup), costs (the app shows estimates and actual usage; link Mistral's pricing page), build from source (Flutter stable, JDK 17, the user-level `gradle.properties` pointer, keystore setup), and the release process; verify every command and section is accurate by following the install section on the device and the build section locally.
- [ ] 4.2 Write `PRIVACY.md` at the repo root covering the privacy-policy spec's four requirements (what is recorded and where it goes, what the app does not do, how data is deleted, linked from the README); verify the README links to it and each spec requirement maps to a policy section.

## 5. Release workflow and the v1.0.0 release (design P4-D2)

- [ ] 5.1 Write `.github/workflows/release.yml`: on tag pushes matching `v*`, set up Java 17 and Flutter stable, run `flutter pub get`, `flutter analyze`, and `flutter test`, decode the keystore and `key.properties` from repository secrets, `flutter build apk --release`, and create the GitHub Release named after the tag with `voxtral-live-<tag>.apk` attached; verify the YAML parses and the steps match the README's manual fallback exactly.
- [ ] 5.2 Document the required repository secrets (the base64 keystore and the `key.properties` contents or its four values) in the README's release section; verify the secret names match the workflow exactly.
- [ ] 5.3 Cut v1.0.0: push the `v1.0.0` tag (`pubspec.yaml` is already `1.0.0+1`) and verify the release exists with the APK attached — via the workflow if Actions runs, otherwise manually per the README; record which path was taken and why.

## 6. Dogfood and the friction list (design P4-D5)

- [ ] 6.1 Create `docs/friction-list.md` with the format header (what happened / what was expected / severity: annoying, work impeded, data lost) and the 2–4 week window; verify the file exists and states the format.
- [ ] 6.2 Dogfood: with the release APK installed on the physical device, run real conversations over 2–4 weeks and record each friction as it happens; verify the list has entries from real sessions (or a recorded "no friction" note per week).

## 7. Integration checks

- [ ] 7.1 Run `openspec validate --strict` for this change; verify it passes.
- [ ] 7.2 Run `flutter analyze` and the full `flutter test` suite; verify both are clean (no test hits the live API).
- [ ] 7.3 Tick the "Dogfood for 2–4 weeks; keep a friction list" item in `project-plan.md` (the window ran and the list exists); leave the v1.1 item open as the follow-up change; verify the checkboxes.

## Workflow follow-up

- Review the change (specs + design + tasks) with the user; archive only after tests pass and the review is done.
- Archive the change, which syncs the delta specs into the main specs; verify the archived result with `openspec validate --strict` and `openspec list`.
- After the 2–4 week dogfood window: triage `docs/friction-list.md` into a v1.1 change (top friction points first).
- Play Store distribution stays a later decision (plan §10): when pursued, `PRIVACY.md` is the base for the listing, plus the background-mic demo video (plan §7).
- The deferred Spike C probes (spike-notes 5.2/5.3) stay cancelled (user decision, 2026-10-27); reviving them is a future change's decision, not this one's.
