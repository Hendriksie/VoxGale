# cost-indicator Specification

## Purpose
Make the cost of transcription visible before and during use, and accurate afterwards, so users who pay for their own Mistral API key are never surprised by a bill.

## Requirements

### Requirement: Show estimated cost during a live session
The system SHALL display elapsed session minutes and the estimated cost so far during a live session, using the configured per-minute rate for the realtime model. The elapsed time and the estimate SHALL advance only while capture is active; a paused period SHALL NOT add to either.

#### Scenario: Session running
- **WHEN** a live session has been capturing for some minutes
- **THEN** the UI shows elapsed minutes and the estimated cost accumulated so far, updating while the session captures

#### Scenario: Session paused
- **WHEN** a live session is paused
- **THEN** the elapsed time and the estimated cost stay where they were and do not advance until the session resumes

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

### Requirement: Include the post-session diarization pass in cost visibility
The system SHALL show the additional estimated cost of the post-session diarization pass before it runs, computed as the saved session audio's duration times the configured per-minute rate of the model the pass will use, and the pass SHALL be skippable.

#### Scenario: Session ends with post-pass pending
- **WHEN** a live session ends and the post-session diarization pass is pending
- **THEN** the UI shows the pass's estimated cost and lets the user run or skip it

#### Scenario: User skips the post-pass
- **WHEN** the user skips the offered post-session diarization pass
- **THEN** no batch request is sent, no cost is incurred for the pass, and the provisional transcript is kept

### Requirement: Keep displayed rates in one configured place
The system SHALL take displayed per-minute rates from a single configuration source that names each model and its rate, so cost displays cannot silently disagree with each other.

#### Scenario: Rate displayed
- **WHEN** any cost estimate is displayed
- **THEN** the rate used matches the configured rate for the model actually used
