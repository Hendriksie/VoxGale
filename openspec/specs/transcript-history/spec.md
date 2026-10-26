# transcript-history Specification

## Purpose
Keep finalized transcripts on the device, browsable and searchable, with export to text or Markdown, so past conversations remain useful after the session ends.

## Requirements

### Requirement: Save finalized transcripts locally
The system SHALL save every finalized live session and file transcription to on-device history, including the transcript text, speaker labels, timestamps, duration, date, and the billed audio duration reported by the API.

#### Scenario: Session finalized
- **WHEN** a live session or file transcription is finalized
- **THEN** it appears in the history list with its date, duration, and speaker-labelled transcript

### Requirement: Browse and search history
The system SHALL show the history list and let the user search transcripts by their text content.

#### Scenario: Search finds a past conversation
- **WHEN** the user searches history for a term that appears in a past transcript
- **THEN** matching transcripts are shown

### Requirement: View a saved transcript
The system SHALL let the user open a saved transcript and read it with its speaker labels and timestamps intact.

#### Scenario: Open a past transcript
- **WHEN** the user opens a transcript from history
- **THEN** the full speaker-labelled transcript is displayed as it was finalized

### Requirement: Export transcripts
The system SHALL export a transcript to plain text or Markdown via the system share sheet.

#### Scenario: User exports
- **WHEN** the user exports a transcript
- **THEN** a text or Markdown file containing the speaker-labelled transcript is produced and offered to the share sheet

### Requirement: Delete transcripts
The system SHALL let the user delete individual transcripts and all history, removing the transcript and its associated locally stored audio.

#### Scenario: User deletes a transcript
- **WHEN** the user deletes a transcript from history
- **THEN** the transcript and its local audio are removed and it no longer appears in history

### Requirement: Handle session audio retention
The system SHALL delete a live session's stored audio after its post-session diarization pass completes, unless the user has chosen to keep recordings; the transcript itself is always kept.

#### Scenario: Diarization pass completes
- **WHEN** the post-session diarization pass for a live session completes
- **THEN** the session audio file is deleted by default, and the speaker-labelled transcript is kept

### Requirement: Persist live session audio for the post-session pass
The system SHALL save a live session's audio to app-private storage when the session ends, so the post-session diarization pass can run on it even after an app restart, and SHALL keep it until the pass completes or the transcript is deleted.

#### Scenario: Session audio saved at stop
- **WHEN** a live session is stopped
- **THEN** the session audio is complete and readable in app-private storage

#### Scenario: App restarted before the post-session pass
- **WHEN** the app is restarted after a live session ended but before its post-session diarization pass ran
- **THEN** the saved session audio is still available and the pass can run on it
