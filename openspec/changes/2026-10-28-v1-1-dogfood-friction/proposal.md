# Proposal

## Why

Dogfooding (Phase 4, `docs/friction-list.md`) surfaced two friction items on day one, both the same bug class — **UI state that is computed once and never re-evaluated when the underlying condition changes**:

1. **API-key message is stale** (`annoying`): after adding an API key in Settings, the red missing-key message stays visible until the app is restarted. Removing the key does not bring the message back.
2. **Battery banner is stale** (`annoying`): after granting unrestricted battery access in the system settings and returning to the app, the "Allow unrestricted battery use" banner stays visible.

The plan's Phase 4 says "v1.1 from the top friction points" — these are the first (and currently only) two. Root causes: the settings controller already invalidates `apiKeyProvider` after save/remove, but nothing watches it, so the invalidation is a no-op; the live controller reads the key only inside `start()`, and the battery exemption only inside `_start()`. As a bonus, the fix brings the live screen into compliance with the empty-error-states spec, whose scenario says opening a transcription screen with no key saved shows the missing-key state — today that only happens after a failed Start attempt.

## What Changes

- **Reactive API-key presence** (friction 1): a new presence-only provider `apiKeyPresentProvider` (FutureProvider<bool>) derives `key != null && key.isNotEmpty` from the existing `apiKeyProvider` — the key value never propagates beyond the store/provider layer. The settings controller's existing invalidations now cascade into it.
  - The live session controller watches it (`ref.listen` in `build()`) and keeps the missing-key state current: shown while no key is saved and no capture is in flight, dismissed as soon as a key is saved. Presence changes during a running session are ignored (the session is unaffected; the next start re-checks the key).
  - The file transcription controller replaces its one-shot `_loadKeyPresence()` with the same listener, so its inline missing-key banner also tracks presence (shows when the key is removed, hides when saved).
- **Battery prompt re-check** (friction 2): the live session controller gains `recheckBatteryExemption()` — re-reads `captureService.isBatteryOptimizationIgnored()` and updates `batteryPromptNeeded` (dismisses the prompt once the app is exempt; never raises the prompt when no session context exists). The live screen becomes a `ConsumerStatefulWidget` with a `WidgetsBindingObserver` that calls it when the app resumes.
- **Not in this change**: the dogfood window keeps running (the friction list stays open for more items — this change is the first triage, not the last); v2 ideas stay parked; no changes to capture, the Mistral layer, or storage.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `empty-error-states`: the missing-key precondition state SHALL track the key's current presence — shown while no key is saved, dismissed as soon as a key is saved, without restarting the app (both transcription screens).
- `live-transcription`: the battery-exemption check SHALL be repeated when the app returns to the foreground, and the prompt SHALL be dismissed once the app is exempt, without restarting the app.

## Impact

- **New code**: `apiKeyPresentProvider` in `lib/session/session_providers.dart`; presence listeners in `LiveSessionController` and `FileTranscriptionController`; `LiveSessionController.recheckBatteryExemption()`; the live screen's lifecycle observer.
- **Changed code**: `lib/app/live_session_screen.dart` (ConsumerStatefulWidget + WidgetsBindingObserver), `lib/session/live_session_controller.dart`, `lib/session/file_transcription_controller.dart`, `lib/session/session_providers.dart`.
- **No new dependencies**: Riverpod's `ref.listen` in `build()` and `WidgetsBindingObserver` are framework/Riverpod built-ins.
- **Tests**: controller tests for the reactive missing-key state (mutation-then-read: seed no-key → the state shows without a start attempt; save → it clears; remove → it shows again) over a fake key store with provider overrides; a controller test for `recheckBatteryExemption` (fake capture service: exempt → the flag clears; not exempt within a session context → it stays); a widget test that the screen calls recheck on lifecycle resume (fake controller records the call); a file-transcription controller test for the reactive banner flag. `flutter analyze` + the full suite stay clean; no test hits the live API.
- **Device smoke** (the fixes are UI-state behavior the user hit on device): save/remove the key in Settings and verify the live screen's missing-key state appears/disappears without a restart; grant the battery exemption in the system settings and verify the banner disappears on return (and reappears when revoked during a session).
- **Assumptions**: the dogfood window (Phase 4 task 7.2) and the Phase 4 archive stay open until the window closes; this v1.1 change lands independently, per the plan ("v1.1 from the top friction points").
