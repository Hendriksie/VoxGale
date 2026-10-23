## OpenSpec
- Never implement before reading the change proposal in openspec/changes/.
- Implementation stays scoped to the approved change; new ideas go into a
  new proposal, not the current one.
- Run `openspec validate --strict` before claiming a task complete.
- Archive only after tests pass and the change is reviewed.

## This project
- No new dependencies without a one-line justification in the proposal.
- Never hit the live Mistral API from tests.
- Anything touching mic/foreground service needs a physical-device smoke test
  step in tasks.md (emulators lie about background capture).
