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
