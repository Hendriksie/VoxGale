# Changelog

All notable changes to VoxGale are documented in this file. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [v1.2.0] - 2026-10-28

### Changed

- New launcher icon: a white speech bubble with a waveform, replacing the
  previous waveform glyph.

## [v1.1.0] - 2026-10-28

### Fixed

- The missing-API-key message now appears and disappears immediately when
  the key is saved or removed in Settings — no app restart needed (both the
  live and the file transcription screens).
- The "allow unrestricted battery use" prompt is re-checked when the app
  returns to the foreground and dismisses once the exemption is granted.

## [v1.0.0] - 2026-10-28

Initial release.

### Added

- **Live transcription** — realtime speech-to-text while you record, with a
  turn-grouped transcript, pause/resume, and background capture via an
  Android foreground service (microphone type) that keeps working while the
  app is backgrounded or the screen is off.
- **Speaker labels** — a post-session diarization pass replaces the
  provisional transcript with speaker-labelled text; file transcriptions
  are diarized directly. Live diarization is available as a per-session
  toggle.
- **File transcription** — import an audio file from device storage and
  transcribe it with speaker labels (Mini or Small model, chosen per file
  or via the settings default).
- **Transcript history** — every session and file transcription is saved
  locally, with full-text search, a detail view, and export to plain text
  or Markdown.
- **Cost visibility** — elapsed time and an estimated cost while recording,
  and the actual billed usage after every session and transcription.
- **Settings** — Mistral API key entry validated with a cheap test request
  and stored in the device's secure storage (Android Keystore); default
  batch model and language hint preferences.
- **Signed release builds** — release APKs are signed with a release key
  kept out of version control and published to GitHub Releases on `v*` tags.

### Fixed

- Pausing a live session stops the session clock and billing: no audio is
  sent and no cost accrues while paused (previously the clock kept running
  and keep-alive silence was billed).
