# Design

## Context

The export-and-share flow lives in `lib/app/transcript_export.dart`:
`shareTranscriptExport()` (used by the history detail view and the live
screen's post-session card via `showTranscriptExportSheet` in
`lib/app/transcript_share_sheet.dart`) and `shareAgentReply()` (agent reply
share on the history detail view). Both write the export to a temp file in
`Directory.systemTemp` (the app cache dir on Android, no platform channel
needed) and call `SharePlus.instance.share(ShareParams(files: [XFile(...)]))`
— file only, no `text:`, no explicit `mimeTypes:`. share_plus 13.3.1 derives
the MIME type from the file extension (`.txt` -> `text/plain`, `.md` ->
`text/markdown`) and, on Android, fires `ACTION_SEND` with `EXTRA_STREAM`
pointing at a `content://<pkg>.flutter.share_provider/...` URI, granting
read permission to every resolved target. The transcript content is therefore
only reachable via the file stream; `EXTRA_TEXT` is absent. See proposal.md
for the motivation (Vibe app opens empty when shared to).

## Goals / Non-Goals

**Goals:**

- The share offer carries the export text in `EXTRA_TEXT` AND the export file
  in `EXTRA_STREAM`, MIME type `text/plain`, so both text-consuming and
  file-consuming targets receive the content.
- The change stays inside `transcript_export.dart`; the injectable share seam
  (`ShareParams`-taking function parameter / providers) is unchanged, so
  widget tests keep running off-device.
- A size guard keeps very large transcripts shareable (file-only) instead of
  failing the whole intent.

**Non-Goals:**

- No deep link / prefill into the Vibe app (no documented contract —
  `docs/ideas.md`); no changes to the export builders, temp-file write, bottom
  sheet, or send-to-agent flow; no UI for the share result (parked idea).

## Decisions

- **D1 — Dual payload: `ShareParams(text: content, files: [xfile],
  mimeTypes: ['text/plain'])`.** share_plus's Android side adds `EXTRA_TEXT`
  alongside `EXTRA_STREAM` when `text` is set, and still grants the file URI.
  This is the minimal change that fixes text-consuming targets while keeping
  file-consuming targets working. Alternative considered: text-only share
  (`ShareParams(text: content)`) — rejected because it drops the file for
  file-only targets (some save-to-drive/files apps) and loses the `.md`
  filename.
- **D2 — Label the shared file `text/plain` even for the Markdown export.**
  Without an explicit MIME the `.md` export goes out as `text/markdown` and
  `text/plain`-only targets are not offered it. The shared file keeps its
  `.md` name, so file-saving targets still store the right extension; text
  targets receive raw Markdown, which is still readable. Alternative: keep
  the derived MIME for `.md` — rejected because it reproduces the original
  mismatch.
- **D3 — Size guard: `text:` only when the export text fits in 500 KB on the
  wire, file-only above.** `EXTRA_TEXT` rides in the intent's binder
  transaction (~1 MB total shared by all extras) and Android parcels strings
  as UTF-16 (~2 bytes per Dart code unit), so the guard compares
  `content.length * 2` against 500 KB — that leaves headroom for the file URI,
  subject, and chooser extras. Alternative: truncate or chunk the text —
  rejected as complexity for no behavioral gain (the file carries the full
  content). Note: share_plus 13.3.1's `ShareParams` has no `mimeTypes` field;
  the per-file MIME comes from `XFile.mimeType`, so the `.md` file is shared
  with an explicit `mimeType: 'text/plain'` (D2) instead.
- **D4 — Keep the temp-file + injectable-share seam.** No new platform
  channel; the params construction (what `text`/`mimeTypes` are passed) is
  directly unit-tested by injecting a recording fake, and the real
  `SharePlus.instance.share` call is exercised by the device smoke test in
  tasks.md (a fake does not replace coverage of the production share step —
  per the project's agent lessons).

## Risks / Trade-offs

- **[Risk] The Vibe app (`ai.mistral.chat`) may still not prefill a new chat
  from shared text — there is no documented share-target contract
  (docs.mistral.ai, researched 2026-11-01).** → Mitigation: the device smoke
  test dumps the app's intent filters (`adb shell dumpsys package
  ai.mistral.chat`) and shares plain text after the fix; if Vibe still opens
  empty, record the finding in `docs/ideas.md` — the remaining options are
  manual paste / `chat.mistral.ai/work`, or asking Mistral for a prefill
  deep link.
- **[Risk] Some targets may show the text and the file as two attachments
  (apparent duplication).** → Mitigation: none needed; the text is the same
  content as the file, and targets that read only one extra are unaffected.
- **[Risk] 500 KB threshold is an estimate of the binder limit, not a
  measured constant.** → Mitigation: conservative by design; the failure
  mode above the threshold is graceful (file-only) rather than a crash.

## Migration Plan

Not applicable — no data or schema changes; the behavior change ships with
the next app version. Rollback is reverting `transcript_export.dart`.

## Open Questions

- Whether `ai.mistral.chat` consumes shared text into a new chat — answered
  only on a physical device (this machine has none); see the smoke test in
  tasks.md. This does not change the specs: the dual payload is correct for
  any text-consuming target regardless of Vibe's behavior.
