# Spec Delta

## ADDED Requirements

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

## MODIFIED Requirements

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
