# settings Specification

## Purpose
Let the user manage their own Mistral API key and transcription preferences, with the key stored securely and sent only to Mistral's API.

## Requirements

### Requirement: Store the API key in secure storage
The system SHALL store the user's Mistral API key in the device's secure storage (Android Keystore-backed), and SHALL NOT write it to plaintext files, shared preferences, logs, crash reports, or source code.

#### Scenario: Key saved
- **WHEN** the user saves an API key
- **THEN** the key is retrievable by the app for API calls but is not visible in plaintext storage or logs

### Requirement: Validate the API key on entry
The system SHALL validate a newly entered API key with a cheap test request against the Mistral API before treating it as saved, and SHALL show whether validation succeeded.

#### Scenario: Valid key entered
- **WHEN** the user enters a valid API key
- **THEN** validation succeeds and the key is saved

#### Scenario: Invalid key entered
- **WHEN** the user enters an invalid API key
- **THEN** validation fails, an error is shown, and the key is not saved

#### Scenario: Validation request cannot reach the API
- **WHEN** the validation request fails because the network or the API is unreachable
- **THEN** an error is shown, the key is not saved, and the user can retry validation

### Requirement: Send the key only to Mistral over TLS
The system SHALL send the API key only to `api.mistral.ai` over TLS.

#### Scenario: API request made
- **WHEN** the app makes any API request
- **THEN** the key is attached only to requests to `api.mistral.ai` over HTTPS/WSS

### Requirement: Manage model and language preferences
The system SHALL let the user set a default batch model (Mini or Small) and a language hint (a pinned language or automatic detection), applied to new transcriptions.

#### Scenario: Preference applied
- **WHEN** the user sets the default batch model to Small and starts a file transcription without choosing a model
- **THEN** the Small model is used

#### Scenario: Language pinned
- **WHEN** the user pins a language in settings
- **THEN** new transcriptions use that language instead of auto-detection

### Requirement: Remove the API key
The system SHALL let the user remove the stored API key, after which no transcription can run until a new key is saved.

#### Scenario: Key removed
- **WHEN** the user removes the API key
- **THEN** the key is deleted from secure storage and transcription screens show a missing-key state

### Requirement: Provide a settings screen in the app's main navigation
The system SHALL provide a settings screen reachable from the app's main UI (not debug-only), showing whether an API key is saved without displaying it, and offering key entry with validation, key removal, and transcription preferences.

#### Scenario: User opens settings
- **WHEN** the user opens the settings screen from the app's main UI
- **THEN** the screen shows the key status (saved or not, never the key itself) and the transcription preferences

#### Scenario: No key saved
- **WHEN** the user opens the settings screen and no API key is saved
- **THEN** a missing-key state is shown and saving a key is offered

### Requirement: Persist transcription preferences
The system SHALL persist the default batch model and the language hint locally so they survive an app restart, and SHALL apply them to every new transcription that does not choose a model explicitly, including post-session diarization passes.

#### Scenario: Preference survives a restart
- **WHEN** the user sets the default batch model to Small, restarts the app, and starts a file transcription without choosing a model
- **THEN** the Small model is used

#### Scenario: Post-session pass uses the preference
- **WHEN** a live session ends and the post-session diarization pass is offered without a model chosen for the pass
- **THEN** the pass uses the configured default batch model
