# Design

## Context

The dogfood friction list's first two items (2026-10-28, both `annoying`) are the same bug class: UI state computed once, never re-evaluated. The live session controller reads the API key's presence only inside `start()` (setting `missingApiKey` on failure) and the battery exemption only inside `_start()` (setting `batteryPromptNeeded`); the file transcription controller loads key presence once in `build()`. The settings controller already invalidates `apiKeyProvider` after `saveKey`/`removeKey`, but nothing watches that provider, so the invalidation is currently a no-op. See proposal.md for the friction wording and the delta specs for the behavior changes.

## Goals / Non-Goals

**Goals:**

- The missing-key state on both transcription screens tracks the key's current presence — shown while no key is saved, dismissed as soon as one is saved, no restart (empty-error-states delta).
- The battery prompt is re-checked when the app returns to the foreground and dismissed once the app is exempt (live-transcription delta).
- The controller state stays coherent (the controller owns state; the screens render it) and a running session is never disturbed by key-presence changes.

**Non-Goals:**

- No capture, Mistral-layer, or storage changes; no new dependencies.
- The dogfood window keeps running; this change is the first v1.1 triage, not the last.
- The banner's visibility semantics when no session context exists stay as they are (the prompt is session-scoped; the re-check only dismisses within an existing session context).

## Decisions

### V11-D1 — Presence-only provider + `ref.listen` in the controllers

A new `apiKeyPresentProvider` (FutureProvider<bool>) in `session_providers.dart` derives `key != null && key.isNotEmpty` from the existing `apiKeyProvider`. The key value never propagates past the provider (only the bool does), matching the existing rule that the key is read only through the store and the lib/mistral clients. The settings controller's existing `ref.invalidate(apiKeyProvider)` calls now cascade: presence re-computes, and any watcher reacts. Both controllers watch the presence with `ref.listen(apiKeyPresentProvider, …)` inside `build()` (Riverpod 3's documented pattern for a notifier reacting to a provider) and keep their `missingApiKey` flags current. The live controller's start-path key check stays (authoritative at action time).

*Rationale:* secure storage has no change notification, so a change-stream on `ApiKeyStore` would need manual emits anyway; the invalidation cascade is the Riverpod-idiomatic path and the settings controller already performs the invalidations — the fix wires up the missing watcher.

*Alternatives considered:* a `Stream` on `ApiKeyStore` (rejected: secure storage cannot notify; the store would emit manually, duplicating the invalidation); deriving the missing-key display in the screens (rejected: the controller owns state — deriving in the screen leaves the controller's state stale and incoherent).

### V11-D2 — When the missing-key state shows or dismisses

The live controller's presence listener: when no key is saved and no capture is in flight, it sets the missing-key error state (`phase: error`, `missingApiKey: true`, the standard message); when a key is saved and the current state is that missing-key error, it clears back to a fresh idle state. While a capture is in flight the listener returns immediately — a running session keeps its transcript, and the next `start()` re-checks the key.

*Rationale:* this matches the empty-error-states spec scenario (opening a transcription screen with no key shows the missing-key state — which the previous start-attempt-only behavior violated) and the user's expectation (set → message goes; removed → message returns). The idle/done transcript being replaced by the missing-key state when the key is removed is the spec's intended precondition behavior; the finished transcript remains in history.

*Alternatives considered:* only clearing the message when a key is saved and never showing it proactively (rejected: the user explicitly expects the message back when the key is removed, and the spec scenario wants it on open); showing it even mid-session (rejected: it would cover a running transcript).

*Known boundary:* a key removed mid-session takes effect at the next presence change or restart — the running session is unaffected by design.

### V11-D3 — Battery re-check on foreground resume, dismiss-only semantics

`LiveSessionController.recheckBatteryExemption()` re-reads `captureService.isBatteryOptimizationIgnored()` and updates `batteryPromptNeeded`. It early-returns when neither a capture is in flight nor the prompt flag is set (no session context — the prompt is session-scoped per the spec, so a fresh launch must not raise it), and otherwise sets the flag to `!ignored`: exempt → the prompt is dismissed; still not exempt → the flag stays/sets within the session context. The live screen becomes a `ConsumerStatefulWidget` with a `WidgetsBindingObserver`; on `AppLifecycleState.resumed` it calls the re-check. The observer lives in the screen, not the controller — controllers are not widgets and have no lifecycle.

*Rationale:* the user grants the exemption in the system settings and returns — resume is the precise trigger. Dismiss-only (within a session context) keeps the spec's "prompt when a session is about to start or while it is active" scoping.

*Alternatives considered:* a timer-based re-check (rejected: resume is precise and cheap); re-checking inside the banner's widget (rejected: the banner unmounts when dismissed — the re-check must live above it); making the banner auto-hide without asking the platform (rejected: the app cannot know the exemption changed without a platform call).

## Risks / Trade-offs

- [Presence provider recompute races a start attempt] → Mitigation: the start path still reads the key authoritatively; the listener only adjusts the display state.
- [Key removed mid-session] → Mitigation: the listener ignores presence changes while a capture is in flight (documented boundary above).
- [Battery re-check fires a platform-channel call on every resume] → Mitigation: the early-return guard skips the call when no session context and no prompt exist.
- [The banner's manual Dismiss is per-widget-state] → Mitigation: unchanged — dismissal stays local until the flag itself changes (granted exemption), which is exactly the reported friction.

## Migration Plan

No data migration, no schema change, no released-behavior dependency. The v1.0.0 release is unaffected; this lands as v1.1 (the next version bump happens when the release is cut). Rollback is reverting the change's commits.

## Open Questions

- None blocking. The dogfood window may surface more friction — this change covers the first two items only; later items become follow-up changes.
