# Proposal

## Why

Sharing a transcript to a chat-style app (observed with the Mistral Vibe
mobile app, `ai.mistral.chat`, on device 2026-11-03) opens the target app
without the content: the export flow in `lib/app/transcript_export.dart`
shares a file only (`ShareParams(files: [XFile(...)])`), so the Android share
intent carries the transcript solely in `EXTRA_STREAM` with no `EXTRA_TEXT`.
Text-consuming share targets (chat and note apps) read `EXTRA_TEXT`, get null,
and open empty. Additionally the Markdown export goes out as `text/markdown`,
which `text/plain`-only targets do not match. The fix is small and makes every
text-consuming share target work, not only file-consuming ones.

## What Changes

- `shareTranscriptExport()` and `shareAgentReply()` in
  `lib/app/transcript_export.dart` share BOTH the export text (`text:` ->
  Android `EXTRA_TEXT`) and the export file (`files:` -> `EXTRA_STREAM`),
  with the file's MIME type set explicitly to `text/plain` (via
  `XFile(path, mimeType: 'text/plain')` — share_plus 13.3.1 takes the per-file
  MIME from the `XFile`, there is no `ShareParams.mimeTypes`) for both the
  plain-text and the Markdown export.
- Size guard: when the export text exceeds 500 KB, share the file only (no
  `text:`), because `EXTRA_TEXT` rides in the intent's binder transaction
  (~1 MB total) and a very long transcript could make the whole share intent
  fail.
- Spec deltas MODIFY the two export requirements in `transcript-history`
  ("Export transcripts" and "Export the agent reply") to require the dual
  payload and the `text/plain` MIME type, with the size-guard exception.
- Explicitly NOT in this change: a deep link / prefill into the Vibe app (no
  documented contract — see `docs/ideas.md`, researched 2026-11-01), changes
  to the export builders, the temp-file write, the bottom-sheet UX, or the
  send-to-agent flow. Surfacing the `ShareResult` in the UI is parked as a
  separate idea.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `transcript-history`: "Export transcripts" (and, by reference, "Export a
  just-ended session from the live screen") and "Export the agent reply" —
  the share-sheet offer SHALL carry the export text in `EXTRA_TEXT` in
  addition to the export file, with MIME type `text/plain`; file-only when
  the text exceeds the size guard.

## Impact

- Code: `lib/app/transcript_export.dart` only (`shareTranscriptExport`,
  `shareAgentReply`, plus a small guard helper/constant). No new dependencies
  — `share_plus` 13.3.1 is already a direct dependency, and its Android side
  already adds `EXTRA_TEXT` when `text` is set while still granting the file
  URI (`FLAG_GRANT_READ_URI_PERMISSION` + per-target `grantUriPermission`).
- Tests: `test/app/transcript_export_test.dart` — assert the shared
  `ShareParams` carry `text`, `files`, and `mimeTypes: ['text/plain']`, plus
  new cases for the size guard (text omitted above the threshold, file still
  shared). Widget tests are unaffected: the share step stays behind the
  injectable provider. No live API in tests.
- Device smoke: the share sheet is a platform channel — a physical-device
  step goes into tasks.md (dump `ai.mistral.chat`'s intent filters, share
  plain text to Vibe, verify whether a new chat opens with the transcript).
  This machine has no Android device: the step stays pending user
  verification.
- Docs: `CHANGELOG.md` Unreleased entry.
