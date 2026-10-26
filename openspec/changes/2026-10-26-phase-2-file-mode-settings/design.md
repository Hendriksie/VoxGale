# Design

## Context

Phase 1 (archived) shipped live mode end-to-end: the home screen is the live session screen, finalized sessions persist through `SessionRepository` over a Drift database (`sessions` + `segments`, schema v1), the post-session diarization pass runs through `DiarizationPass` on `BatchTranscriptionClient`, and the API key lives in `SecureStorageApiKeyStore` with a debug-only entry on the debug route. The batch client, the secure key store, and the persistence layer already implement everything Phase 2's flows need; what is missing is the UI and orchestration around them (file mode, settings, history) plus the small storage and client extensions below. See proposal.md for motivation and the delta specs for requirements.

## Goals / Non-Goals

**Goals:**

- File mode end-to-end: pick → estimate → transcribe (`diarize=true`) → speaker-labelled result, saved to history.
- A production settings screen (key validation, key removal, persisted preferences) replacing the debug-only key entry.
- Cost visibility for file transcriptions: estimate before upload and while running; actual usage on the result.
- History list/search/detail/export/delete over live sessions and file transcriptions, including re-offering a skipped or failed post-session pass from the detail view.
- Keep every Mistral call behind the `lib/mistral/` interfaces; keep the UI storage-agnostic behind repository interfaces.

**Non-Goals:**

- Spike-harness removal (a later change, after the deferred Spike C probes); the harness stays on the debug route.
- Phase-3 polish: the full empty/error-state system, audio-focus handling, battery/wake-lock review.
- Speaker enrollment UI, a live-diarization toggle UI, iOS.
- Multiple file picks per transcription — one file per transcription, per spec.

## Decisions

### P2-D1 — File transcription flow and placement

`lib/session/file_transcription_controller.dart` (a Riverpod `Notifier`, alongside the live session controller and `DiarizationPass`) orchestrates the flow: pick file → measure duration → estimate → `BatchTranscriptionClient.transcribe(diarize: true, model, language)` → save to `SessionRepository` → expose a state machine (`idle → picked → running → result | error`). `lib/app/file_transcription_screen.dart` renders it: picker entry, progress with elapsed time and running estimate, then the speaker-labelled transcript (reusing `transcript_widgets.dart`). The controller depends on the existing providers (`batchTranscriptionClientProvider`, `sessionRepositoryProvider`, `mistralConfigProvider`) plus the new preferences provider; the UI never touches the API or storage directly.

*Rationale:* the same shape as the Phase-1 pass — a small, testable orchestrator with the Mistral layer and repository injected, so tests mock them and never hit the live API.

*Alternative considered:* putting the flow in the spike's batch screen — rejected; the spike harness is debug-only and stays untouched.

### P2-D2 — Measuring the file's duration before upload

The pre-upload cost estimate needs the file's real audio duration. `just_audio` reads it through the platform media APIs (Android `MediaExtractor`), which handle the common picked formats (mp3, m4a, wav, ogg, flac) — a new dependency with a one-line justification in the proposal.

*Rationale:* the spec pins "estimated cost before the request is sent, computed from the file's audio duration measured locally before upload".

*Alternatives considered:* parsing WAV headers only — rejected (most picked files are compressed; estimates would be wrong or absent); estimating from file size — rejected (bitrates vary ~10×, so the estimate could be off by an order of magnitude).

### P2-D3 — Storage: schema v2 (source columns + preferences) and repository extension

- `sessions` gains `source` (`live` | `file`) and `sourceFileName` (nullable); a new `Preferences` table holds one row (default batch model, language hint). Schema version 1 → 2 with a create-table + add-column migration; existing rows default to `live`.
- `SessionRepository` gains `listSessions({String? searchQuery})` (newest first; search matches segment text) and `deleteAllSessions()` (deletes each session's audio file too, reusing the existing delete path).
- A separate `PreferencesRepository` interface (get/save) with a Drift implementation — preferences are not sessions, so they get their own seam and provider.

*Rationale:* Drift is the project's chosen local store; a preferences table avoids a new `shared_preferences` dependency, and interface-first keeps the UI mockable (Phase-1 pattern).

*Alternative considered:* storing preferences in `shared_preferences` — rejected (one more dependency for two fields; Drift is already the local store of record).

*Alternative considered:* FTS5 for search — rejected; a `LIKE` query over joined segments is proportionate at personal-history scale and keeps the migration trivial.

### P2-D4 — Settings screen and key validation

`lib/app/settings_screen.dart` with a small `SettingsController` notifier: key status (saved/not saved, never the value), key entry → validate → save to `SecureStorageApiKeyStore` only after validation succeeds, key removal, and the two preferences. Validation is a cheap `GET /v1/models` behind a new `KeyValidationClient` interface in `lib/mistral/` (Dio implementation with explicit finite timeouts — the dio gotcha). 200 → save; 401/403 → invalid-key error; unreachable → error state, not saved, retryable (settings spec).

*Rationale:* `GET /v1/models` costs nothing and proves the key is accepted; the hard constraint keeps the call inside `lib/mistral/` behind an interface, so tests mock it.

*Alternative considered:* validating with a tiny real transcription — rejected (costs money and audio upload for every key save).

### P2-D5 — Cost indicator for file mode

The estimate is `duration × MistralConfig.rateForModel(selectedModel) / 60`, shown before upload (P2-D2 duration) and accruing with elapsed time while running. The running estimate reuses a clock/ticker seam like Phase 1's `SessionClock` — a fake clock in tests, the system clock in production, with direct test coverage of the production clock (Phase-1 lesson: an injected seam's production implementation still gets direct coverage). The API's reported usage replaces the estimate on completion.

*Rationale:* one configured rate source (`MistralConfig`) already exists; the cost-indicator spec requires the estimate to match the model actually used.

### P2-D6 — History UI and export

`lib/app/history_screen.dart` (list newest-first with date, duration, source, model + a search field) and `lib/app/history_detail_screen.dart` (metadata header, the speaker-labelled transcript via `transcript_widgets.dart`, actions: export, delete; plus the pass re-offer when applicable). Export builds plain text or Markdown from the stored segments (format chosen in a small bottom sheet), writes it to a temp file (`path_provider`, already a direct dependency), and shares it via `share_plus`'s share sheet. Delete (with confirmation) and delete-all reuse the repository; deleting a session removes its audio file.

*Rationale:* `share_plus` is the standard share-sheet plugin; generating the file ourselves keeps the export content testable without platform channels.

### P2-D7 — Re-offering a skipped or failed post-session pass

The history detail view offers the pass when the stored session is `provisional`, has an `audioPath`, and the audio file still exists — the file-existence check matters because a successful pass leaves a stale `audioPath` in the row (documented in `diarization_pass.dart`). Running the offer reuses `DiarizationPass.estimateCost`/`run` unchanged in shape.

`DiarizationPass` gains a `model` parameter (defaulting to the batch Mini model): the settings preference now applies to passes that don't choose a model (settings spec), so both `estimateCost` and `run` compute with `config.rateForModel(model)`. With the default preference (Mini) the Phase-1 behavior is unchanged.

*Rationale:* one pass implementation, two entry points (session end, history detail) — no duplicated orchestration.

*Alternative considered:* a separate re-run flow in the history layer — rejected (duplicates the pass's persist-and-delete-audio logic).

### P2-D8 — Navigation

The live session screen's app bar gains three actions — file mode, history, settings — pushed as `MaterialPageRoute`s (the existing navigation style); the `kDebugMode`-gated debug action stays. The debug hub loses its key-entry tile (the settings screen replaces it); the spike screens stay.

*Rationale:* named routes would be a new pattern for three screens; the project already pushes routes imperatively.

## Risks / Trade-offs

- **[Batch duration/size limits remain unverified (deferred Spike C 5.2)]** → a very long file may be rejected by the API. Mitigation: the error state explains the limit and keeps the selected file (file-transcription spec); a chunking fallback is a later change.
- **[Duration probing can fail for an exotic format]** → the pre-upload estimate is omitted and the estimate accrues from elapsed time while running, with the per-minute rate always visible. Mitigation: honest partial display; the common formats are covered by `MediaExtractor`.
- **[Drift schema bump on existing dev installs]** → migration is create-table + add-column with defaults; no released users, no data migration beyond defaults.
- **[Stale `audioPath` after a successful pass]** → the re-offer checks file existence, not just the stored path; history delete already tolerates a missing file.
- **[Three new dependencies]** (`file_picker`, `share_plus`, `just_audio`) → each has a one-line justification in the proposal; all are standard, well-maintained plugins for platform channels Flutter does not expose.
- **[Search is `LIKE`-based]** → fine at personal-history scale; revisit with FTS5 only if history grows large.
- **[Key validation adds one request per save]** → `GET /v1/models` is free; it runs only on explicit save, never on app start.

## Migration Plan

Not a user-facing migration — the app has no released users. Storage: Drift schema 1 → 2 (add `source`/`sourceFileName` columns with defaults, create the `Preferences` table); regenerate `app_database.g.dart` with `build_runner` and commit it. Code: the debug-only key entry is removed from the debug hub once the settings screen exists; navigation is additive. The spike harness, the live session flow, and the capture service are untouched. Rollback is not applicable pre-release; the change is additive and each screen degrades to the Phase-1 behavior if removed.

## Open Questions

- **Exact Markdown/text export layout** (heading style, timestamp formatting) — presentation detail; safe to decide during implementation against the existing transcript widgets.
- **Which languages the language-hint dropdown lists** — content detail; a short common-languages list plus "Automatic"; safe to decide during implementation.
- **Whether the file-mode result screen offers a shortcut into history** — minor UX; default is no shortcut (the transcript is reachable from the history action).
