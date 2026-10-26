# Spec Delta

## ADDED Requirements

### Requirement: Provide a file transcription entry point in the app's main UI
The system SHALL provide an entry point to file transcription mode in the app's main navigation, which opens the system file picker for an audio file.

#### Scenario: User opens file mode
- **WHEN** the user taps the file transcription action in the app's main UI
- **THEN** the system file picker opens for selecting an audio file

## MODIFIED Requirements

### Requirement: Show progress for long files
The system SHALL show a progress state while a file is being transcribed, displaying elapsed time and the running estimated cost. The batch transcription API returns a single response, so partial transcript text is not available and SHALL NOT be displayed while transcribing.

#### Scenario: Long file transcribing
- **WHEN** a long file is being transcribed
- **THEN** a progress state with elapsed time and the running estimated cost is shown, and no partial transcript text is displayed

#### Scenario: Transcription completes
- **WHEN** a file transcription completes
- **THEN** the speaker-labelled transcript replaces the progress state

### Requirement: Save and export the result
The system SHALL save the finished transcript to local history together with its source file name, the model used, and the billed audio duration reported by the API, and SHALL support exporting it.

#### Scenario: Transcription completes
- **WHEN** a file transcription completes
- **THEN** the transcript is saved to history with its source file name, model, and billed usage, and can be exported to text or Markdown via the system share sheet
