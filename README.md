# VoxGale

Live conversation transcription for Android, powered by your own
[Mistral AI](https://mistral.ai) API key. Record a conversation — including
while the app is backgrounded or the screen is off — and read it as clean,
speaker-labelled text. Or import an audio file and transcribe it the same way.

The app talks to `api.mistral.ai` directly with your key. There are no
accounts, no cloud sync, and no telemetry — see [PRIVACY.md](PRIVACY.md).

## Features

- **Live transcription** — realtime speech-to-text while you record, with a
  turn-grouped transcript, pause/resume, and background capture via an
  Android foreground service (microphone type) that keeps working while the
  app is backgrounded or the screen is off.
- **Speaker labels** — a live session gets a post-session diarization pass
  that replaces the provisional transcript with speaker-labelled text; file
  transcriptions are diarized directly. Live diarization is available as a
  per-session toggle.
- **File transcription** — import an audio file from device storage and
  transcribe it with speaker labels (Mini or Small model, your choice per
  file or via the settings default).
- **Transcript history** — every session and file transcription is saved
  locally, with full-text search, a detail view, and export to plain text or
  Markdown.
- **Cost visibility** — elapsed time and an estimated cost while recording,
  and the actual billed usage after every session and transcription. You pay
  Mistral directly, per minute of audio; see
  [Mistral's pricing](https://mistral.ai/pricing).

## Install

1. Download `voxgale-<version>.apk` from the
   [Releases](https://github.com/Hendriksie/opencode-openspec-test/releases)
   page.
2. Open the downloaded file and allow "install unknown apps" for the app you
   downloaded it with (browser or file manager), if prompted.
3. Open the app, go to **Settings**, and enter your Mistral AI API key. The
   key is validated with a cheap test request and stored in the device's
   secure storage (Android Keystore) — it is sent only to `api.mistral.ai`.

> **Updating:** install a newer APK over the existing one. Uninstall any
> debug build first — a differently-signed build cannot install over it.

## Build from source

Requires the Flutter SDK (stable channel) and a JDK 17.

```sh
flutter pub get
flutter run                     # debug build on a connected device
flutter test                    # unit + widget + integration tests (no network)
flutter build apk --release
```

Notes:

- **JDK 17:** if your machine's default Java is newer than 17 (or a JRE
  without `javac`), point Gradle at a JDK 17 in the *user-level*
  `~/.gradle/gradle.properties` — never commit it, it is machine-local:

  ```properties
  org.gradle.java.home=/path/to/jdk-17
  ```

- **Android SDK:** set `ANDROID_SDK_ROOT` (or `android/local.properties`).
- **Release signing:** release builds sign with a keystore that is *not* in
  version control. Generate it once and keep it safe — losing it means
  installed copies can never be updated:

  ```sh
  keytool -genkeypair -v -keystore android/app/upload-keystore.jks \
    -alias upload -keyalg RSA -keysize 2048 -validity 10950 \
    -dname "CN=VoxGale, O=Hendriksie, C=NL"
  ```

  then write `android/key.properties` (gitignored) with the passwords you
  entered:

  ```properties
  storeFile=upload-keystore.jks
  keyAlias=upload
  storePassword=<store password>
  keyPassword=<key password>
  ```

  Back up `android/app/upload-keystore.jks` and `android/key.properties`
  (password manager or encrypted storage). A release build without
  `android/key.properties` fails with a clear message — it never falls back
  to a debug signature.

## Release

Pushing a tag matching `v*` (for example `v1.0.0`) runs
[`.github/workflows/release.yml`](.github/workflows/release.yml): it runs
`flutter analyze` and `flutter test`, builds the release APK, and publishes
a GitHub Release with the APK attached as `voxgale-<tag>.apk`.

### Repository secrets (one-time setup)

The workflow signs the APK with the release key from two repository secrets
(Settings → Secrets and variables → Actions):

- `UPLOAD_KEYSTORE` — the base64 of `android/app/upload-keystore.jks`:

  ```sh
  base64 -w0 android/app/upload-keystore.jks | gh secret set UPLOAD_KEYSTORE
  ```

  (macOS: `base64 -i android/app/upload-keystore.jks | gh secret set UPLOAD_KEYSTORE`)

- `KEY_PROPERTIES` — the contents of `android/key.properties`:

  ```sh
  gh secret set KEY_PROPERTIES < android/key.properties
  ```

### Manual release (fallback when Actions is unavailable)

```sh
flutter build apk --release
cp build/app/outputs/flutter-apk/app-release.apk voxgale-v1.0.0.apk
gh release create v1.0.0 voxgale-v1.0.0.apk --title v1.0.0
```

## Development

- Project plan and milestones: [project-plan.md](project-plan.md)
- Change workflow: [OpenSpec](openspec/) — every change starts with a
  proposal in `openspec/changes/`; validate with `openspec validate --strict`
  before claiming a task done.
- Dogfooding friction list: [docs/friction-list.md](docs/friction-list.md)

## Privacy

See [PRIVACY.md](PRIVACY.md).
