# Spec Delta

## MODIFIED Requirements

### Requirement: Show estimated cost for file transcription
The system SHALL show the estimated cost of a file transcription before the request is sent and while it runs, computed from the file's audio duration measured locally before upload times the configured per-minute rate of the model selected for that file.

#### Scenario: File transcription starts
- **WHEN** a file transcription starts
- **THEN** the estimated cost for the file is visible before the result arrives

#### Scenario: File transcription running
- **WHEN** a file transcription is running
- **THEN** the displayed estimate accrues with the elapsed time while the transcription runs

### Requirement: Show actual usage after each session and transcription
The system SHALL display the actual billed audio duration reported by the API and the resulting actual cost after each live session and file transcription, including the usage of a post-session diarization pass when it ran.

#### Scenario: Session ends
- **WHEN** a live session ends and the API reports usage
- **THEN** the actual audio duration and actual cost are shown alongside the estimate

#### Scenario: Post-session pass completes
- **WHEN** the post-session diarization pass completes and reports usage
- **THEN** the pass's actual audio duration and actual cost are shown alongside the live session's

#### Scenario: File transcription completes
- **WHEN** a file transcription completes and the API reports usage
- **THEN** the actual audio duration and actual cost are shown on the result view
