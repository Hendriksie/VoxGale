# Tasks

## 1. Open-source boilerplate

- [x] 1.1 Add `LICENSE` (MIT, copyright Wesley Hendriks 2026 — user decision 2026-10-28). (Verified: file created.)
- [x] 1.2 Add `CHANGELOG.md` in Keep a Changelog format: `## [Unreleased]`, then `## [v1.1.0] - 2026-10-28` (dogfood friction fixes) and `## [v1.0.0] - 2026-10-28` (initial release), written from the archived OpenSpec proposals. (Verified: file created.)
- [x] 1.3 Add `CONTRIBUTING.md`: OpenSpec proposal flow for changes, issues for bugs, tests never hit the live Mistral API, device smoke rule for mic/foreground-service changes. (Verified: file created.)
- [x] 1.4 Add `SECURITY.md`: private vulnerability reporting via GitHub security advisories; data-flow summary (audio/transcripts only to `api.mistral.ai` under the user's key). (Verified: file created.)
- [x] 1.5 Add `.github/ISSUE_TEMPLATE/bug_report.md` (app version, Android version/device, what happened / expected / steps / logs — never the API key). (Verified: file created.)

## 2. Release notes

- [x] 2.1 Draft paste-ready release notes for the existing releases as `docs/release-notes/v1.0.0.md` and `docs/release-notes/v1.1.0.md`, matching the CHANGELOG sections plus the install/privacy pointer line. (The GitHub MCP on this box is read-only for releases — the user pastes these in the GitHub UI, task 7.2.) (Verified: both files created.)
- [x] 2.2 Update `.github/workflows/release.yml`: the publish step extracts the `## [<tag>]` section from CHANGELOG.md (awk, exact-heading match) and passes it as `--notes`, falling back to the current one-liner when the tag has no section; update the workflow header comment. (Verified: awk extraction tested locally for v1.1.0, v1.0.0, and a missing tag (fallback); YAML parses.)

## 3. Repository hygiene and README

- [x] 3.1 `git mv project-plan.md docs/project-plan.md`; add a header note marking it the historical v1 record superseded by the OpenSpec flow, with ideas moved to `docs/ideas.md`. (Verified: `git mv` done; header note added.)
- [x] 3.2 Fix the two links to the plan: `README.md` (Development section) and `docs/friction-list.md` (header). (Verified: both updated.)
- [x] 3.3 Add `docs/ideas.md` (parking lot): seed with project-plan §9 (agent integration, automatic speaker naming, live translation, widgets, Wear OS, iOS, wake word), the open dogfood observation (session lost when the battery exemption is revoked mid-session), and the cancelled Phase-0 spike questions (API limits, 50%-off batch tier, `speaker_references` wire format); state the promote-to-OpenSpec flow. (Verified: file created.)
- [x] 3.4 Update the README Development section: link `CHANGELOG.md`, `CONTRIBUTING.md`, `docs/ideas.md`, and `docs/project-plan.md` (historical). No other README restructuring in this group — the screenshots/header section waits for the assets (task 6.3). (Verified: links added; all linked files exist.)

## 4. CI workflow

- [x] 4.1 Add `.github/workflows/ci.yml`: `flutter analyze` + `flutter test` on pushes to master and on pull requests; first-party Flutter setup (pinned `FLUTTER_VERSION` 3.47.8, `ubuntu-24.04`, extracted to `$HOME`) mirroring release.yml; no JDK/Android SDK (analyze + VM tests don't build Android); `contents: read` permission. (Verified: YAML parses.)

## 5. Icon redesign

- [x] 5.1 Generate 2–3 launcher-icon redesign options (vector-first SVG, rasterized with ImageMagick at 512²) keeping the `#FF7000` background; preview them to the user. (Verified: 3 options generated + previewed — see design.md D7.)
- [x] 5.2 User picks an option (record the pick in design.md D7). (Verified: option A — speech bubble + waveform — picked 2026-10-28; recorded in design.md D7.)
- [x] 5.3 Apply the chosen icon: rasterize to `android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png` (48/72/96/144/192) and rewrite `drawable/ic_launcher_foreground.xml` so the adaptive-icon vector matches the raster glyph (108dp canvas, glyph inside the 66dp safe zone). (Verified: all 5 densities written as 8-bit RGBA with transparent corners, matching the previous format; the vector path data was rendered to SVG and compared side-by-side with the raster — glyph geometry identical; XML well-formed; the anydpi-v26 comment updated.)
- [x] 5.4 Verify: `flutter analyze` clean; full `flutter test` suite passes; `openspec validate 2026-10-28-go-public --strict` passes. If a physical device is reachable, install a debug build and confirm the launcher icon on device. (Verified: `flutter analyze` — no issues; `flutter test` — 353/353 passed; `openspec validate --strict` — change valid. No physical device on this box (no adb) — the on-device launcher-icon check is a user follow-up, non-blocking: the icon is static artwork, no mic/foreground-service behavior involved.)

## 6. Repository presentation assets (after the icon pick)

- [x] 6.1 Generate the README header/banner image from the final icon (`docs/assets/readme-header.png`, 1280×360: glyph + wordmark on `#FF7000`) — added to the repo and wired into the README top. (Verified: rendered + visually checked.)
- [x] 6.2 Generate the GitHub social-preview image (1280×640, `docs/assets/social-preview.png`) from the final icon — the user uploads it in the repo settings (task 7.2). (Verified: rendered + visually checked.)
- [x] 6.3 Capture app screenshots (live session, history, settings) from a device or emulator into `docs/assets/screenshots/`, and add a Screenshots section to the README. (Verified: the user captured three screenshots on the Pixel and added them; renamed to `live-session.png`, `file-transcription.png`, `history.png`; a Screenshots section with the three images was added to the README between Features and Install.)

## 8. Post-review fixes (user-reported)

- [x] 8.1 Fix `SECURITY.md`: the private-vulnerability-reporting link 404s while the repository is private (the feature exists only on public repositories). Reworded to name the advisories route as the preferred path once public, with a GitHub noreply email fallback that works in both states. (Verified: the 404 reproduced via an unauthenticated fetch; the reworded file names both routes.)

## 7. Validation and go-public (user steps)

- [x] 7.1 Run `openspec validate 2026-10-28-go-public --strict` and `openspec validate --specs --strict`; run `flutter analyze` and the full `flutter test` suite. All clean. (Verified: change valid under `--strict`; main specs valid under `--specs --strict`; analyze clean; 353/353 tests pass.)
- [x] 7.2 User steps in the GitHub UI (this environment cannot do them): paste the drafted notes into the v1.0.0 and v1.1.0 releases from `docs/release-notes/`; set the repo description ("Live conversation transcription for Android, powered by your own Mistral API key") and topics (`flutter`, `android`, `dart`, `transcription`, `speech-to-text`, `mistral`); enable Discussions with an "Ideas" category. (Verified 2026-10-28: user pasted the release notes and set description/topics; API confirms the description, all six topics, and has_discussions=true.)
- [x] 7.2b Upload `docs/assets/social-preview.png` as the repository social preview (Settings → General → "Social preview"). (Verified 2026-10-28 after the user uploaded it: the repo page's og:image now serves from repository-images.githubusercontent.com at 1280×640 with the #FF7000 banner — the custom image is live.)
- [x] 7.3 Commit and push the change; verify GitHub renders the license badge, the changelog link, and the README links. (Verified: committed in group commits and pushed to origin/master.)
- [x] 7.4 Flip the repository to public (the final user step, after 7.1–7.3 are green). (Verified 2026-10-28: API reports visibility=public; the repo page shows the Public badge, the MIT license badge, the Security tab, and the rendered README with header image and screenshots; the SECURITY.md advisories link now resolves to the sign-in page instead of 404.)

## Workflow follow-up

- Review the change with the user; archive only after the icon pick lands (tasks 5.3–6.x) and tests pass.
- Archive syncs the delta specs into the main specs; verify with `openspec validate --strict`.
- The icon ships with the next `v*` tag — no version bump in this change.
