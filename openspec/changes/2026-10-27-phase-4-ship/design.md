# Design

## Context

Phases 0–3 are archived: four production screens over `lib/session/` controllers, capture in the foreground service, all Mistral code behind `lib/mistral/` interfaces, 29 test files that mock the Mistral layer, and a Phase-3 device session that verified audio focus, the wake lock, and battery drain. What remains before dogfooding is packaging and distribution: release builds still sign with the debug key (`android/app/build.gradle.kts` line 36), the README is the Flutter template, there is no privacy policy, and the Phase-0 spike harness still ships its WAV assets inside every release APK (pubspec assets are unconditional). One committed file is machine-local: `android/gradle.properties` pins `org.gradle.java.home` to a path that exists only on the dev machine, which breaks any clean-checkout build (including CI). See proposal.md for motivation and the delta specs for requirements.

## Goals / Non-Goals

**Goals:**

- Release APKs signed with a real release key, built reproducibly from a `v*` tag and published to GitHub Releases with the APK attached (release-distribution spec).
- Release artifacts free of debug/spike surface — code, menu entry points, and bundled assets (release-distribution spec).
- A README that takes a stranger from the repo to a working install, and a privacy policy that states plainly what is recorded and where it goes (privacy-policy spec).
- Dogfooding kicked off with a friction list (plan Phase 4).

**Non-Goals:**

- v1.1 itself — the friction-list triage into follow-up change(s) happens after dogfooding; v2 ideas (plan §9) stay parked.
- Play Store distribution, iOS, speaker enrollment UI, live-diarization UI, and the "quality vs. battery" chunking setting (Phase-3 battery review already decided against it for v1).
- Any change to app runtime behavior, the Mistral client surface, or the storage schema.
- The deferred Spike C probes (spike-notes 5.2/5.3) — cancelled (user decision, 2026-10-27); the Phase-0 open questions they would have answered (API limits, the 50%-off batch tier, the `speaker_references` wire format) stay open.

## Decisions

### P4-D1 — Release signing: standard Flutter keystore layout, fail-loud with no debug fallback

Generate the release keystore once at `android/app/upload-keystore.jks` with `keytool`, plus `android/key.properties` (storeFile, keyAlias, storePassword, keyPassword). `android/app/build.gradle.kts` loads `key.properties` and configures `signingConfigs.release`; when the file is missing the build **fails** with a `GradleException` naming the missing configuration and pointing at the README — the Flutter template's silent debug fallback is removed, because the spec requires that no debug-signed artifact is ever produced. The existing `android/.gitignore` already ignores `key.properties`, `**/*.keystore`, and `**/*.jks` (lines 10–14), so no ignore change is needed — a task verifies it with `git check-ignore`. The keystore and `key.properties` are backed up at creation time (password manager / encrypted storage) and the README documents that a lost key means installed copies can never be updated.

*Rationale:* a debug-signed APK is machine-local and effectively publicly signable; it also gives no update path (a differently-signed update requires uninstall). The spec's install scenario — a later release installs over the previous one — requires a stable release key.

*Alternatives considered:* keep debug signing — rejected (no update path, public key); Play App Bundle — rejected (plan §10: sideload APK first); CI-only signing with the key never on the dev machine — rejected (the manual release fallback needs the key locally; the key lives locally and enters CI only as encrypted repository secrets).

### P4-D2 — Release workflow: tag-triggered, verify-then-build, signing key from secrets

`.github/workflows/release.yml`, triggered on pushes of tags matching `v*`: checkout → setup Java 17 (temurin) → setup Flutter (stable, `subosito/flutter-github-action`) → `flutter pub get` → `flutter analyze` → `flutter test` (the suite mocks the Mistral layer and never hits the network, so CI is safe) → decode the keystore and `key.properties` from repository secrets into the build directory → `flutter build apk --release` → create the GitHub Release named after the tag with the APK attached as `voxtral-live-<tag>.apk` (`gh release create`). The README documents the identical manual steps (local build + `gh release create` or the GitHub UI) as the fallback when Actions is unavailable, producing the same signed artifact.

The committed machine-local `org.gradle.java.home` in `android/gradle.properties` breaks clean-checkout builds — the path exists only on the dev machine. This change moves the setting to the user-level `~/.gradle/gradle.properties` (created locally by a task, documented in the README's build-from-source section) and removes it from the committed file, which becomes machine-independent; the workflow then relies on `JAVA_HOME` from setup-java.

*Rationale:* tag-push-to-release makes shipping a one-command act and keeps artifacts reproducible from the tag; running analyze + test on the release path enforces the project's testing rules where it matters most.

*Alternatives considered:* manual-only releases — rejected (the spec's tag scenario); building an AAB — rejected (sideloading needs an APK); skipping tests in CI — rejected (they are cheap and network-free); leaving `org.gradle.java.home` committed and stripping it in the workflow — rejected (leaves a landmine for every other machine; fix the repo instead).

### P4-D3 — Harness removal scope and verification

Remove `lib/spike/` (five files: the three spike screens, spike providers, spike task handler), `lib/app/debug_hub_screen.dart`, the `kDebugMode` debug route and app-bar action (plus the now-unused import) in `lib/app/live_session_screen.dart`, `assets/spike/sample.wav` and `assets/spike/reference_tone.wav` with their pubspec asset entries, and `test/app/debug_hub_test.dart` — its still-valid home-screen assertions (live screen is home, no spike links) move into `test/app/live_session_screen_test.dart` if not already covered there. The harness is self-contained: only the debug hub and the live screen reference it, so removal is pure deletion plus two small edits. Verification: `flutter analyze` clean, full `flutter test` clean, the release APK lists no `assets/spike/` entries (`unzip -l`), and the installed release app shows no debug menu.

*Rationale:* pubspec assets are bundled unconditionally, so the spike WAVs ship inside release APKs today; dead debug code rots and confuses the next reader.

*Alternatives considered:* keep the harness behind `kDebugMode` — rejected (the assets still ship in release builds); keep the screens but drop the assets — rejected (half-removal keeps dead code). The deferred Spike C probes that once needed the harness are cancelled (user decision, 2026-10-27), so nothing is lost by removing it whole.

### P4-D4 — README and privacy policy content

The README replaces the Flutter template: what the app is (the plan's one-liner), what it does (live + file transcription, speaker labels, history with export, cost visibility), **install** (download the APK from Releases → allow "install unknown apps" for the source → open the APK → first launch: Settings → enter and validate the Mistral API key; uninstall any debug build first — signature mismatch), **costs** (the app shows an estimate before/during and actual billed usage after each session; link Mistral's pricing page rather than hardcoding rates that will drift), **build from source** (Flutter stable, JDK 17, the user-level `gradle.properties` JDK pointer, keystore setup), and **release** (tag `v*` publishes via the workflow; manual fallback). `PRIVACY.md` at the repo root, dated and in plain language, covers exactly the privacy-policy spec's four requirements and is linked from the README.

*Rationale:* the README is the first thing a stranger sees, and its install section is the release-distribution spec's acceptance path; the policy is required for Play distribution later (plan §7) and is honest now.

*Alternatives considered:* keep the template README — rejected; put the policy inside the app's settings — rejected for v1 (a sideloaded app has no store listing to carry it; a repo doc linked from the README is the available channel; an in-app link can come in v1.1 if wanted).

### P4-D5 — Dogfood protocol and the friction list

Install the release APK on the physical device (the Pixel used for all smoke tests; uninstall the debug build first), use the app for real conversations for 2–4 weeks, and record friction in `docs/friction-list.md`: one entry per friction — what happened, what was expected, and a severity (annoying / work impeded / data lost). The file is created with a header stating the format and the window. The list is the sole input to the v1.1 triage, a follow-up change after dogfooding, per the plan.

*Rationale:* the plan's Phase 4 is "dogfood, keep a friction list, then v1.1 from the top friction points"; a versioned repo file works offline and survives, and keeps dogfooding independent of the issue tracker.

*Alternatives considered:* GitHub issues with a label — rejected for v1 (couples dogfooding to the tracker); it can be adopted at triage time if the list grows.

## Risks / Trade-offs

- [Keystore lost → installed copies can never be updated] → Mitigation: the keystore and `key.properties` are backed up at creation time (a task), and the README documents that a lost key blocks updates forever.
- [Keystore committed or leaked into CI logs → anyone can sign malware as the app] → Mitigation: `android/.gitignore` already ignores the key files (verified with `git check-ignore`); the workflow decodes secrets only into the build directory and never prints them.
- [Actions unavailable or secrets misconfigured → the tag push does not publish] → Mitigation: the workflow fails loudly when secrets are missing (no silent unsigned artifact, per P4-D1); the README's manual steps produce the same release; v1.0.0 is cut manually if needed and the reason recorded.
- [Machine-local `org.gradle.java.home` breaks other machines' builds] → Mitigation: moved to the user-level `gradle.properties` in this change (P4-D2); the committed file becomes machine-independent.
- [Release install over a debug-signed dev build fails on signature mismatch] → Mitigation: uninstall the debug build first; documented in the README install steps and the dogfood task.
- [Dogfooding doesn't happen / the friction list rots] → Mitigation: the friction list is a tracked artifact with a defined format and window; the v1.1 triage is the explicit follow-up.

## Migration Plan

No released users, no data migration, no schema change. The only behavioral delta is the missing debug menu in debug builds. Rollback is reverting the change's commits; the signing key lives outside git, so rollback never loses it.

## Open Questions

- Whether GitHub Actions runs on the distribution repo — answered when the `v1.0.0` tag is pushed; the manual fallback covers the no case.
- Play Store timing — a later decision per plan §10, not this change.
