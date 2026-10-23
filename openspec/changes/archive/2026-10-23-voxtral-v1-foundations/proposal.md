# Proposal

## Why

The Voxtral live transcription app exists only as a plan (`project-plan.md`); no code has been written. Before building features, the three riskiest paths — realtime WebSocket streaming, background mic capture, and batch diarization — must be proven end-to-end, because each can kill the project on its own (Android background restrictions, protocol surprises, API limits).

Why now: Mistral released the Voxtral 3 family in Public Preview on 2026-10-20. The plan was written against a mix of Voxtral 2 and Voxtral 3: its pinned realtime model ID (`voxtral-mini-transcribe-realtime-2602`) is the previous generation, and its central constraint ("realtime is not compatible with `diarize`") no longer holds — Voxtral 3 realtime supports opt-in diarization and turn detection (mutually exclusive within one session). Building on the stale contract would waste the spikes. This change re-grounds the plan in the verified Voxtral 3 API and proves the core paths.

## What Changes

- **Flutter project scaffold** (Android-first): git-initialized project, Material 3 with Mistral orange `#FF7000` light + dark themes defined upfront.
- **`lib/mistral/` client layer**: all Mistral API code behind abstract interfaces — a realtime WebSocket client and a batch REST client implementing the Voxtral 3 protocol contract (base64 `input_audio.append` chunks, `session.update` before the first audio chunk, event normalization, reconnect + local audio buffering). UI and service code never call the API directly.
- **Phase-0 spikes** (proof, not production code):
  - **Spike A — realtime path**: mic → PCM16 stream → realtime WebSocket → text on screen, exercised in both session modes (turn detection and diarization).
  - **Spike B — background capture**: same pipeline via Android foreground service (microphone type), screen off for 30+ minutes.
  - **Spike C — batch path**: audio file → `POST /v1/audio/transcriptions` with `diarize=true` → speaker-labelled transcript. The client is built and the happy path verified on device (task 5.1); the limits probe and speaker-reference verification (5.2–5.3) are **deferred to a future version** (user decision, 2026-10-23) — the file-transcription feature lands in Phase 2 regardless.
- **v1 capability baseline**: six capability specs (below) adopted as the requirement baseline for the app. This change implements Phase 0 only; Phases 1–4 land as follow-up changes that implement — and where needed modify — these specs.
- **`openspec/config.yaml` context fix**: replace the stale "realtime is not compatible with `diarize`" constraint with the Voxtral 3 reality (a realtime session takes `diarize` XOR `turn_detection`; v1 default is turn detection live + post-session offline diarization, with live diarization available as a per-session toggle).

## Capabilities

### New Capabilities

- `live-transcription`: record live audio (including backgrounded/screen-off via a foreground service), stream it to the Voxtral realtime API, and show the transcript as it is spoken.
- `file-transcription`: import an audio file from device storage and transcribe it via the batch API with speaker labels.
- `speaker-attribution`: speaker-labelled transcripts — offline diarization by default, optional live diarization per session, and named speakers via reference clips.
- `settings`: user-managed Mistral API key (validated, stored in secure storage), model preferences, and language hints.
- `transcript-history`: local, on-device transcript history with search and export to text/Markdown.
- `cost-indicator`: visible session minutes and estimated cost during use, actual usage after each session.

### Modified Capabilities

None — the project has no existing specs.

## Impact

- **Greenfield**: creates the Flutter app at the repository root (`pubspec.yaml`, `lib/`, `android/`). No existing app code is touched.
- **New dependencies** (one-line justification each):
  - `flutter_riverpod` — stream-friendly state management; realtime text deltas map naturally to reactive UI.
  - `record` — mic capture as a PCM16 stream that feeds both the WebSocket and the local audio file.
  - `flutter_foreground_task` — Android foreground service with `microphone` type to keep capture alive screen-off.
  - `web_socket_channel` — WebSocket client for the realtime API (no official Dart SDK exists).
  - `dio` — multipart REST client for batch transcription (no official Dart SDK exists).
  - `flutter_secure_storage` — Keystore-backed storage for the user's API key.
  - `drift` — SQLite local storage for transcript history with search.
  - `mocktail` (dev) — mocks the Mistral WebSocket/REST layer in tests.
- **Android platform**: `RECORD_AUDIO` runtime permission; foreground service declared with `microphone` type plus the `FOREGROUND_SERVICE_MICROPHONE` permission (API 34+).
- **No backend, no accounts**: the app talks to `api.mistral.ai` directly with the user's own key over TLS.
- **Testing**: unit tests mock the Mistral layer (mocktail) and never hit the live API; spikes are manual proof runs against the live API with a real key.
