# Contributing to VoxGale

Thanks for your interest in VoxGale — live conversation transcription for
Android, powered by your own [Mistral AI](https://mistral.ai) API key.

## Reporting bugs

Open an [issue](https://github.com/Hendriksie/VoxGale/issues) using the bug
report template. Include the app version (the release you installed), your
Android version and device, what happened, what you expected, and steps to
reproduce. Attach logs or screenshots if you have them — **never include
your Mistral API key**.

## Proposing changes

VoxGale uses [OpenSpec](openspec/) for change management:

1. Start with a proposal in `openspec/changes/` (`openspec new change
   "<name>"`), describing the why, the what, and the affected
   capabilities.
2. Implement against the proposal's tasks; run
   `openspec validate --strict` before claiming a task done.
3. Archive the change after the tests pass and the change is reviewed
   (`openspec archive`), which syncs the delta specs into the main specs.

Ideas that are not ready for a proposal yet live in
[docs/ideas.md](docs/ideas.md) — feel free to add yours there.

## Development setup

See [README.md](README.md) → "Build from source" (Flutter stable channel +
JDK 17).

## Rules

- Never hit the live Mistral API from tests — mock the WebSocket/REST
  layer (mocktail).
- Never hardcode, log, or commit API keys.
- Anything touching the microphone / foreground service needs a
  physical-device smoke test — emulators lie about background capture.
