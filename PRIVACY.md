# Privacy Policy — VoxGale

_Last updated: 2026-10-29_

VoxGale is a personal transcription app. It records audio from your
device's microphone and sends it to Mistral's API for transcription, using
an API key you provide. This policy states what the app records, where the
data goes, and how it is deleted. It applies to the Android app distributed
as an APK from this repository's Releases.

## What the app records

- **Microphone audio** while a live session is recording. A foreground
  service keeps capture alive while the app is backgrounded or the screen is
  off. Live session audio is saved to the app's private storage so the
  post-session speaker-labelling pass can run on it.
- **Audio files you import** for file transcription. The file stays where
  you picked it; the app reads it to upload it and does not copy it into
  app-private storage.
- **Transcripts** — the text produced from your audio — saved locally in the
  app's on-device database.
- **Your Mistral API key**, stored in the device's secure storage (Android
  Keystore-backed).

## Where the data goes

- **Audio and transcripts are sent to Mistral's API** (`api.mistral.ai`)
  over an encrypted connection (HTTPS/WSS), authenticated with your API key.
  Mistral processes the audio to produce the transcript. Mistral's handling
  of the audio is governed by Mistral's privacy policy and the terms of your
  Mistral account.
- **The API key is sent only to `api.mistral.ai`**, over TLS, and is never
  written to logs, plaintext files, shared preferences, or crash reports.
- **The app checks GitHub Releases for newer versions** — at most once a
  day on app start, and when you tap "Check for updates" in Settings. The
  check is an unauthenticated request for the public release list to
  `api.github.com`; it sends no API key, no account, and no other user
  data.
- **Nothing else leaves the device** — apart from the Mistral API calls
  and the update check above, the app makes no network requests.

## What the app does not do

- No user accounts or sign-up.
- No cloud sync or backup of transcripts or audio.
- No analytics, telemetry, advertising identifiers, or crash reporting sent
  from the device.
- No sale or sharing of your data. The only third party that receives your
  audio and transcripts is Mistral, under your own API key and account.

## Where data is stored

All transcripts and session audio are stored locally on your device, in the
app's private storage (other apps cannot read it).

## How to delete your data

- **Delete a transcript:** open it in the History screen and delete it. This
  removes the transcript and any retained session audio for it.
- **Delete all history:** the History screen offers deleting all saved
  transcripts and their audio.
- **Delete everything:** uninstalling the app removes all of its data
  (transcripts, session audio, and the stored API key) from the device.

## Session audio retention (live sessions)

Live session audio is kept in app-private storage only so the post-session
speaker-labelling pass can run on it:

- After a successful pass, the audio is deleted automatically.
- If you skip the pass or it fails, the audio is kept so the pass can be
  retried later from the transcript's detail view; deleting the transcript
  deletes the audio.

## Questions

This app is a personal project. If you have questions about this policy,
open an issue in this repository.
