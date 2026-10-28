# Dogfood friction list

Phase 4 of [project-plan.md](../project-plan.md): dogfood the v1.0.0 release
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

### 2026-10-28 — Battery flaky message

- **Date** — 2026-10-28
- **What happened** — After granting unrestircted battery access in adnroid and going back to the application, the "Allow unrestricted battery use" message is still visibile.
- **What you expected** — After granting unrestricted access, the message should go away automatically.
- **Severity** — `annoying`

## Weekly notes

<!-- One line per week: sessions run, or "no friction this week". -->
