# Spec Delta

## Purpose

Import an audio file from device storage and transcribe it with the Mistral batch transcription API using the user's own key, producing a speaker-labelled transcript with timestamps.

## ADDED Requirements

### Requirement: Import an audio file
The system SHALL let the user pick an audio file from device storage for transcription.

#### Scenario: User picks a supported audio file
- **WHEN** the user picks an audio file via the system file picker
- **THEN** the file is selected and its transcription starts

#### Scenario: User picks an unsupported file
- **WHEN** the user picks a file the transcription API cannot process
- **THEN** a clear error state explains the file is unsupported and no request is sent

### Requirement: Transcribe with speaker labels and timestamps
The system SHALL request batch transcription with speaker diarization and segment timestamps, and SHALL display the transcript as speaker-labelled segments.

#### Scenario: Successful transcription
- **WHEN** a file transcription completes successfully
- **THEN** the transcript shows segments grouped by speaker with start and end times, in chronological order

### Requirement: Offer the batch model choice
The system SHALL let the user choose the batch model (Mini or Small) per transcription, defaulting to the preference set in settings.

#### Scenario: User selects the larger model
- **WHEN** the user selects the Small model for a file
- **THEN** that file is transcribed with the Small model regardless of the default preference

### Requirement: Show progress for long files
The system SHALL show transcription progress, displaying partial transcript text as it arrives for long files.

#### Scenario: Long file transcribing
- **WHEN** a long file is being transcribed
- **THEN** a progress state is shown and partial text streams in as it is produced

### Requirement: Save and export the result
The system SHALL save the finished transcript to local history and support exporting it.

#### Scenario: Transcription completes
- **WHEN** a file transcription completes
- **THEN** the transcript is saved to history and can be exported to text or Markdown via the system share sheet

### Requirement: Surface transcription errors
The system SHALL show clear error states for files that are too large or too long for the API, network failures, and API errors, without losing the selected file.

#### Scenario: File exceeds API limits
- **WHEN** the API rejects a file for exceeding duration or size limits
- **THEN** an error state explains the limit, and the user can pick a different file
