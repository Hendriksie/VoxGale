# Proposal

## Why

Phases 0–3 are archived: the v1 feature scope in `project-plan.md` is complete and verified on a physical device, but the app has never been shipped — release builds still sign with the debug key, the README is the Flutter template, there is no privacy policy, and the Phase-0 spike harness and its assets still ride along in every APK. Phase 4 of `project-plan.md` is "Ship & iterate": make v1.0 installable and distributed, then dogfood. Why now: v1 scope is done and hardened, and everything left before dogfooding is packaging, distribution, and cleanup.

## What Changes

- **Signed release builds** (plan §10, sideloading route): a release keystore is generated locally, the keystore and `android/key.properties` are gitignored (never committed), and `android/app/build.gradle.kts` signs release builds with them instead of the debug config. The keystore backup is documented — losing it means never being able to update installed copies.
- **GitHub Releases distribution** (plan §10): a `.github/workflows/release.yml` builds the release APK on `v*` tags and publishes a GitHub Release with the APK attached; manual release steps are documented in the README as the fallback when Actions is unavailable.
- **Release APK hygiene**: the Phase-0 spike harness is removed — `lib/spike/`, `lib/app/debug_hub_screen.dart`, the debug route and app-bar action in the live screen, the `assets/spike/` files with their pubspec entries, and `test/app/debug_hub_test.dart`. The spike assets are bundled into release APKs today (pubspec assets are unconditional); after removal the release artifact contains no debug or spike surface. The deferred Spike C probes (spike-notes 5.2/5.3) are **cancelled** (user decision, 2026-10-27) — they were the harness's only remaining purpose; the Phase-0 open questions they would have answered (API limits, the 50%-off batch tier, the `speaker_references` wire format) stay open.
- **README rewrite**: the Flutter template README is replaced with the real project README — what the app does, features, install (sideload the release APK), setup (Mistral API key), the cost table, a link to the privacy policy, and build/release instructions.
- **Privacy policy** (plan §7): a `PRIVACY.md` at the repo root states plainly what the app records, where audio and transcripts go (Mistral's API under the user's own key, over TLS), that storage is local-only with no accounts, cloud sync, or telemetry, and how data is deleted. Required for Play distribution later; honest now.
- **Dogfood** (plan item 1): the release APK is installed on the physical device and used for real conversations for 2–4 weeks; friction is recorded in `docs/friction-list.md`.
- **Not in this change**: v1.1 itself — after dogfooding, the friction list is triaged into follow-up change(s); v2 ideas (plan §9) stay parked until motivated. Play Store distribution ($25, background-mic review) stays a later decision per plan §10.

## Capabilities

### New Capabilities

- `release-distribution`: the project ships signed, versioned release APKs through GitHub Releases — reproducible from a `v*` tag, installable by sideloading, with install docs, a signing key that is never committed, and no debug/spike surface in release artifacts.
- `privacy-policy`: a privacy policy exists at a stable repo path, states what the app records and where the data goes, and is linked from the README.

### Modified Capabilities

None — no app runtime behavior changes; all nine existing capabilities are untouched.

## Impact

- **Changed code**: `android/app/build.gradle.kts` (release signing config, no debug fallback), `android/gradle.properties` (machine-local `org.gradle.java.home` removed — it breaks clean-checkout builds; moved to the user-level gradle.properties), `lib/app/live_session_screen.dart` (debug route + app-bar action removed), `pubspec.yaml` (spike asset entries removed). `android/.gitignore` already ignores the keystore and `key.properties` — verified, no ignore change needed.
- **Removed code**: `lib/spike/` (5 files), `lib/app/debug_hub_screen.dart`, `assets/spike/` (2 files), `test/app/debug_hub_test.dart`.
- **New files**: `android/key.properties` (gitignored, local only), `.github/workflows/release.yml`, `PRIVACY.md`, `docs/friction-list.md`, rewritten `README.md`.
- **New dependencies**: none — no pub or Gradle dependency is added; the workflow uses the standard Flutter setup action.
- **Signing key**: generated locally with `keytool`, stored outside version control; the README documents the backup step. Never committed — a committed keystore would let anyone sign updates as the app.
- **Testing**: `flutter analyze` and the full `flutter test` suite stay clean after the harness removal (the still-valid home-screen assertions from the debug-hub test move to the live session screen test if not already covered); the release build is verified by installing the APK on the physical device and running one live session and one file transcription. No automated test hits the live API.
- **Mic/foreground-service rule**: the release-build smoke test and the dogfood install exercise the capture path on a physical device, so `tasks.md` includes device smoke steps (emulators lie about background capture — project rule).
- **Migration**: no released users; the Drift schema and all app behavior are unchanged. The only user-visible delta is the missing debug menu in debug builds.
- **Assumptions**: the existing GitHub remote is the distribution repo; one change covers Phase 4 through the dogfood window (Phase 1–3 precedent — one change per phase), so the change is archived after the window closes; the iterate half (v1.1) is a follow-up change after the friction-list triage; the Spike C probes stay cancelled unless a future change revives them.
