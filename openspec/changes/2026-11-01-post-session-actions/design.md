# Design

## Context

The live screen (`lib/app/live_session_screen.dart`) is the app's home: app bar
with three icon actions (file transcription, history, settings — already at
the Material 3 guidance limit of ~3 action icons; less important actions belong
in an overflow menu or in context), a status row, the transcript, `_PassSection`
(visible only in the `passOffered`/`passRunning`/`passFailed` phases), and
`_ControlsBar`. After a session is saved, `LiveSessionState.sessionId` holds the
saved session's id and the phase is `done` (or `passOffered` while the
speaker-label pass is pending). The send-to-agent and export flows already
exist on the history detail screen (change
`2026-10-29-send-transcript-to-agent`): `HistoryDetailController.sendToAgent()`
and the `transcriptExportProvider` share flow in `lib/app/transcript_export.dart`.

UX research (2026-11-01): Material 3 app-bar guidelines (m3.material.io/components/app-bars)
— title + navigation + actions, max ~3 action icons, collapse secondary actions
into the overflow; M3 snackbar guidelines — transient process feedback only,
never a home for next-step actions; general next-step practice (NN/g, Appcues
"UX that drives action") — offer related actions inline at the point where the
task just completed, because discoverability beats tidiness for follow-ups.

## Goals / Non-Goals

**Goals:**

- After a live session is saved, Share and Send to agent are one tap away on
  the live screen, combined with the speaker-label pass offer in one card.
- The actions reuse the exact history-detail flows (export bottom sheet,
  confirm dialog, Markdown payload, reply persistence, sanitized errors) —
  no duplicated behavior.
- The app bar stays at three icons; no overflow menu is added.

**Non-Goals:**

- Actions while a session is recording; on the file-transcription screen;
  streaming the agent reply onto the live screen; editing agents in the app.

## Decisions

1. **Placement: a post-session card in the body, above `_ControlsBar`, shown
   in `done` and `passOffered` phases.** In `passOffered` the card combines the
   existing pass offer (Run = single primary filled button, Skip) with a
   secondary actions row (Share, Send to agent as text buttons); in `done` the
   card shows just the actions row ("Session saved" + Share / Send to agent,
   Send as the primary when an agent is selected). Alternatives rejected:
   app-bar overflow menu (M3-sanctioned for secondary actions but hidden —
   fails the discoverability goal, and the bar is already at the 3-icon
   limit); a snackbar with action (M3: transient feedback only); a separate
   screen (adds navigation for two taps).
2. **Reuse, don't duplicate:** the export bottom sheet (plain text / Markdown)
   is extracted into a small shared widget used by both the live screen and
   the history detail screen; the send-to-agent confirm dialog is likewise
   shared. `LiveSessionController.sendToAgent()` loads the saved record via
   `sessionRepositoryProvider` using `state.sessionId`, builds the payload
   with `transcriptToMarkdown`, calls `agentClientProvider`, and persists the
   reply with `saveAgentReply` — the same steps as
   `HistoryDetailController.sendToAgent()`; state gains `agentSending` and
   `agentError`, rendered as a spinner on the button and the shared
   `ErrorBanner` with retry. To avoid two diverging copies, the payload +
   persist step is factored into a tiny shared helper (e.g. in
   `lib/session/agent_send.dart`) used by both controllers. Alternatives
   rejected: navigating to the history detail screen on send (defeats the
   purpose); duplicating the logic in both controllers (drift risk).
3. **Share from the live screen** opens the same export bottom sheet via
   `transcriptExportProvider`, with the record loaded from the repository —
   the history detail screen's `_showExportSheet` moves into the shared
   widget. Alternatives rejected: sharing raw text without the chooser
   (inconsistent with history).
4. **Send-to-agent availability mirrors the detail view:** enabled when the
   saved session has segments and an agent is selected; with no agent
   selected, tapping shows the same "Select an agent in Settings first."
   snackbar; empty transcript → disabled.
5. **No new dependencies**; no platform channels touched (share stays behind
   the injectable `transcriptExportProvider`).

## Risks / Trade-offs

- **[Two send flows can drift]** → shared helper for payload+persist (decision
  2); controller tests on both screens pin the behavior.
- **[Card crowds a short transcript]** → the card is compact (one title line +
  one actions row); the transcript scrolls above it.
- **[Applies only after archive of the agent change]** → proposal notes the
  dependency; `agent-integration` spec must be in main specs before apply.

## Migration Plan

- No storage or API changes; pure UI/controller addition. Rollback: revert the
  change's commits.

## Open Questions

- Resolved 2026-11-01 (user decision, after device testing): whether the user
  should see the agent's reply right after sending from the live screen. On a
  successful send the live screen now **navigates to the saved transcript's
  history detail view**, where the persisted reply card is shown (this also
  satisfies the spec scenario's "a confirmation is shown" — v1's spinner-only
  success was invisible). On failure the screen stays with the
  `ErrorBanner` retry. No reply preview is rendered on the live screen itself;
  the pass re-offer is not lost either — the history detail re-offers it for a
  provisional session with retained audio.
