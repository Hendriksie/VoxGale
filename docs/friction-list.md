# Dogfood friction list

Phase 4 of [project-plan.md](project-plan.md) (historical v1 plan): dogfood the v1.0.0 release
APK on the physical device for 2–4 weeks (window started 2026-10-28) and
record every friction here, one entry per friction. This list is the sole
input to the v1.1 triage after the window closes.

## Format

Each entry:

- **Date** — when it happened.
- **What happened** — what you did and what the app did.
- **What you expected** — what should have happened.
- **Severity** — `annoying` (cosmetic / UX papercut), `work impeded` (slowed
  you down), `data lost` (transcript / audio / session lost).

## Entries

### 2026-10-28 — API-key flaky message

- **Date** — 2026-10-28
- **What happened** — After adding an API-key, the red message stays visible until I restart the app. Removing the API-key does not show the red message anymore.
- **What you expected** — After updating the API-key, the red message should go away (if its set) or show again (when its removed).
- **Severity** — `annoying`
- **Disposition** — → v1.1 (change `2026-10-28-v1-1-dogfood-friction`): the missing-key state now tracks the key's current presence via a presence-only provider — shown while no key is saved, dismissed as soon as one is saved, no restart.

### 2026-10-28 — Battery flaky message

- **Date** — 2026-10-28
- **What happened** — After granting unrestircted battery access in adnroid and going back to the application, the "Allow unrestricted battery use" message is still visibile.
- **What you expected** — After granting unrestricted access, the message should go away automatically.
- **Severity** — `annoying`
- **Disposition** — → v1.1 (change `2026-10-28-v1-1-dogfood-friction`): the battery exemption is re-checked when the app returns to the foreground; the prompt dismisses once the app is exempt.

### 2026-10-28 — Session lost when the battery exemption was revoked mid-session

- **Date** — 2026-10-28
- **What happened** — Observed during the v1.1 device smoke: a live session was recording (transcript streaming, 0:43 elapsed); the battery exemption was revoked in the system settings (Settings → Apps → VoxGale → Battery → Restricted) while the app was backgrounded; on return the app process had been killed by the system (GrapheneOS battery management) — the session was gone (fresh idle state, nothing saved).
- **What you expected** — The foreground service should keep capture alive through a trip to the system settings; a background kill should at least leave a recoverable trace (the partial transcript or a "session was interrupted" state).
- **Severity** — `data lost`
- **Disposition** — open (observed during the v1.1 smoke; the kill followed the exemption revoke on GrapheneOS — candidate follow-up: detect a dead capture service on resume and offer to recover or restart the session, or warn when the exemption is revoked mid-session).

## Weekly notes

- **2026-10-28** — Dogfooding stopped early by user decision ("time to stop with the dogfooding process and finish it up; new bugs/findings will be proposed when I find them"). One day of real use plus the v1.1 smoke produced 3 findings: 2 stale-UI-state frictions (fixed and device-verified in v1.1, change `2026-10-28-v1-1-dogfood-friction`) and 1 open observation (session lost when the battery exemption was revoked mid-session). New findings will be added here as they come up.
