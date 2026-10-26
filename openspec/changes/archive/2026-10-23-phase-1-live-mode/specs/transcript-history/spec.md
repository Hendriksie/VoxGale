# Spec Delta

## ADDED Requirements

### Requirement: Persist live session audio for the post-session pass
The system SHALL save a live session's audio to app-private storage when the session ends, so the post-session diarization pass can run on it even after an app restart, and SHALL keep it until the pass completes or the transcript is deleted.

#### Scenario: Session audio saved at stop
- **WHEN** a live session is stopped
- **THEN** the session audio is complete and readable in app-private storage

#### Scenario: App restarted before the post-session pass
- **WHEN** the app is restarted after a live session ended but before its post-session diarization pass ran
- **THEN** the saved session audio is still available and the pass can run on it

## MODIFIED Requirements

### Requirement: Save finalized transcripts locally
The system SHALL save every finalized live session and file transcription to on-device history, including the transcript text, speaker labels, timestamps, duration, date, and the billed audio duration reported by the API.

#### Scenario: Session finalized
- **WHEN** a live session or file transcription is finalized
- **THEN** it appears in the history list with its date, duration, and speaker-labelled transcript
