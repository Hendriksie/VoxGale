# Spec Delta

## MODIFIED Requirements

### Requirement: Include the post-session diarization pass in cost visibility
The system SHALL show the additional estimated cost of the post-session diarization pass before it runs, computed as the saved session audio's duration times the configured per-minute rate of the model the pass will use, and the pass SHALL be skippable.

#### Scenario: Session ends with post-pass pending
- **WHEN** a live session ends and the post-session diarization pass is pending
- **THEN** the UI shows the pass's estimated cost and lets the user run or skip it

#### Scenario: User skips the post-pass
- **WHEN** the user skips the offered post-session diarization pass
- **THEN** no batch request is sent, no cost is incurred for the pass, and the provisional transcript is kept

### Requirement: Show actual usage after each session and transcription
The system SHALL display the actual billed audio duration reported by the API and the resulting actual cost after each live session and file transcription, including the usage of a post-session diarization pass when it ran.

#### Scenario: Session ends
- **WHEN** a live session ends and the API reports usage
- **THEN** the actual audio duration and actual cost are shown alongside the estimate

#### Scenario: Post-session pass completes
- **WHEN** the post-session diarization pass completes and reports usage
- **THEN** the pass's actual audio duration and actual cost are shown alongside the live session's
