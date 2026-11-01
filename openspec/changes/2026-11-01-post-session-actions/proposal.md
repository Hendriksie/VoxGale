# Proposal

## Why

Device testing of `2026-10-29-send-transcript-to-agent` (2026-11-01) surfaced
a UX gap: after a live session stops, the only offered action on the home
screen is the speaker-label pass ("Add speaker labels" → Run/Skip). Sharing
the transcript or sending it to an agent requires navigating to History and
opening the transcript — three taps too many for the two most common
follow-ups right after a session. UX research (Material 3 app-bar guidelines:
max ~3 action icons, secondary actions belong in an overflow menu or in
context; snackbar guidelines: transient feedback only, not a place for
next-step actions; general next-step discoverability practice: offer related
actions inline where the task just completed) points to an in-context actions
area on the live screen itself, combined with the existing post-session card.

## What Changes

- After a live session is saved (phases `done` and `passOffered`), the live
  screen shows a post-session card with the just-saved session's actions:
  **Share** (the same plain-text/Markdown export bottom sheet as the history
  detail view) and **Send to agent** (the same confirm dialog and send flow
  as the history detail view), combined with the existing speaker-label pass
  offer when it applies (Run stays the single primary action; Share and Send
  to agent are secondary text buttons).
- `LiveSessionController` gains `shareSavedSession()` / `sendToAgent()` using
  the saved `sessionId`, loading the record from the session repository;
  the send flow reuses the agent client, the Markdown payload, the
  confirm dialog, and reply persistence from the agent-integration change
  (the reply is then visible on the transcript in History).
- The app bar is unchanged (already at the M3 three-action-icon limit;
  secondary actions go in context, not the overflow, for discoverability).
- Spec deltas: ADDED requirements to `live-transcription` (post-session
  actions on the live screen) and `transcript-history` (export a just-ended
  session from the live screen).
- Explicitly NOT in this change: send-to-agent during an active session,
  streaming the agent reply into the live screen, editing the agent from the
  app, actions on the file-transcription screen.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `live-transcription`: new requirement to offer Share and Send to agent for
  a just-saved session on the live screen, combined with the post-session
  speaker-label pass offer.
- `transcript-history`: new requirement to export (share sheet, plain text or
  Markdown) a just-ended session directly from the live screen.

## Impact

- Code: `lib/app/live_session_screen.dart` (post-session card combining the
  pass offer and the new actions; shared export bottom sheet), `lib/session/
  live_session_controller.dart` (`sendToAgent()` with the same payload,
  persistence, and error handling as the history detail flow; state gains
  `agentSending`/`agentError`), possibly a small shared widget for the
  export-sheet/confirm-dialog to avoid duplicating them between the live and
  history detail screens. No new dependencies.
- Tests: controller tests with fake agent client + in-memory repository;
  widget tests for the card's actions per phase (done, passOffered,
  passRunning, active). No live API in tests.
- Docs: `CHANGELOG.md` Unreleased Added entry.
- Depends on `2026-10-29-send-transcript-to-agent` being archived first (its
  `agent-integration` spec must exist in main specs before this change can
  reference the send flow; apply order matters).
