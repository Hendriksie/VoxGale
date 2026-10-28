# Security Policy

## Reporting a vulnerability

VoxGale records audio from your microphone and handles your Mistral API
key. If you find a security issue, please report it privately via
[GitHub's private vulnerability reporting](https://github.com/Hendriksie/VoxGale/security/advisories/new)
— do not open a public issue.

## Scope

- Audio and transcripts are sent only to `api.mistral.ai`, over an
  encrypted connection (HTTPS/WSS), authenticated with your own API key.
- The API key is stored in the device's secure storage (Android
  Keystore-backed) and is never written to logs, plaintext files, shared
  preferences, or crash reports.
- There is no backend operated by this project. The only third party that
  receives your audio and transcripts is Mistral, under your own account
  and key. See [PRIVACY.md](PRIVACY.md) for the full data-flow description.
