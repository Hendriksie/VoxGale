# Proposal

## Why

Phase 1 shipped live mode end-to-end and is archived with the flow verified on a physical device. What remains of v1 is exactly the Phase 2 milestone in `project-plan.md` — file mode + settings — which Phase 1 deliberately deferred: the batch client and the Drift persistence layer already exist, and the API key currently lives behind a debug-only entry. Why now: Phase 1 is archived, the deferred pieces all have their foundations in place, and Phase 2 closes the last unchecked v1 scope items (file transcription, a real settings screen, cost visibility for file mode, transcript history).

## What Changes

- **File transcription mode** (plan item 1): a file-mode entry point on the home screen opens the system file picker for an audio file; the picked file is transcribed via the existing batch client with `diarize=true`, showing a progress state with elapsed time and the running cost estimate (the batch API is one-shot — no partial text streams in), then a speaker-labelled, timestamped transcript view. The model (Mini or Small) is chosen per file, defaulting to the settings preference. The finished transcription is saved to history with its source file name, model, and billed usage.
- **Settings screen** (plan item 2): a production settings screen in the app's main navigation — API key entry validated with a cheap test request before it is saved to secure storage (unchanged: `flutter_secure_storage` only), key removal, and persisted preferences (default batch model, language hint) applied to new file transcriptions and post-session passes that don't choose a model. The debug-only key entry on the debug route is removed once the settings screen replaces it.
- **Cost indicator for file transcription** (plan item 3): the estimated cost of a file transcription is shown before the upload starts — computed from the file's locally measured audio duration times the configured per-minute rate of the selected model — and accrues while the transcription runs; the actual billed usage is shown on the result and stored with the history entry.
- **Transcript history UI** (plan item 4): a history screen in the app's main navigation listing all saved transcripts (live sessions and file transcriptions) newest-first with date, duration, source, and model; full-text search; a detail view; export to plain text or Markdown via the system share sheet; delete individual transcripts and all history (removing the transcript and its locally stored audio).
- **Re-offer of a skipped diarization pass** (Phase-1 follow-up): the history detail view of a live session whose post-session pass was skipped (or failed) offers to run the pass on the retained session audio, with its estimated cost; running it replaces the provisional transcript and deletes the audio on success, exactly as at session end.

## Capabilities

### New Capabilities

None — all five capabilities already exist in the Phase-0 baseline.

### Modified Capabilities

- `file-transcription`: file mode becomes a production flow — main-UI entry point, per-file model choice defaulting to the settings preference, honest progress (elapsed time + running estimate; the batch API streams no partial text), and the finished transcription saved to history with source file name, model, and billed usage.
- `settings`: a production settings screen in the main navigation (key entry with validation, key removal, persisted model/language preferences); the debug-only key entry is replaced.
- `cost-indicator`: file-transcription cost display becomes active — estimate before upload from the locally measured duration and the selected model's configured rate, accruing while running, actual usage on the result and in history.
- `transcript-history`: the history list/search/detail/export/delete UI becomes active, over both live sessions and file transcriptions; each entry identifies its source (live session or imported file name) and model.
- `speaker-attribution`: a skipped or failed post-session diarization pass can be re-offered and run from the transcript's history detail view on the retained session audio.

## Impact

- **New code**: `lib/app/file_transcription_screen.dart` (picker → progress → speaker-labelled result), `lib/app/settings_screen.dart`, `lib/app/history_screen.dart` with a detail view, a file-transcription controller under `lib/session/` (or a new `lib/file/`), storage additions in `lib/storage/` (history list/search queries, a persisted preferences table — Drift schema bump + `build_runner` regen), and a cheap key-validation request in `lib/mistral/` behind the existing client interfaces (never called from UI code directly).
- **Changed code**: `lib/main.dart` / home app bar (navigation entries for file mode, history, settings), `lib/app/debug_hub_screen.dart` (debug-only key entry removed; the spike harness itself stays — its removal is a later change after the deferred Spike C probes), `lib/session/diarization_pass.dart` (the pass flow is re-offerable from the history detail view).
- **New dependencies** (one-line justification each):
  - `file_picker` — system file picker to import an audio file from device storage; no existing dependency provides it.
  - `share_plus` — system share sheet to export transcripts to text/Markdown; the share channel needs a plugin.
  - `just_audio` — reads a picked audio file's duration via the platform media APIs, so the pre-upload cost estimate uses the real duration for any common format.
- **No mic/foreground-service changes**: this phase touches neither capture nor the service, so the physical-device smoke-test rule is not triggered; a device smoke test of the file flow + export is still included because file picking, the share sheet, and secure storage are platform channels (emulators are fine for the rest).
- **No new Mistral surface beyond one validation call**: the realtime and batch clients already implement everything the flows need; only a cheap key-validation request is added, behind the `lib/mistral/` interfaces.
- **Migration**: no released users; the Drift schema gains a preferences table (schema-version bump with a create-table migration). Existing saved sessions are untouched.
- **Testing**: unit tests mock the Mistral layer (mocktail) and never hit the live API; repository tests cover list/search/preferences; production implementations of injected seams get direct test coverage (Phase-1 lesson). Device smoke test: file import → transcribe → export on a physical device.
- **Assumptions**: one change covers all of Phase 2 (Phase-1 precedent); spike-harness removal and Phase-3 empty/error states stay out of scope; preferences live in the Drift store (the project's chosen local store), not a new dependency.
