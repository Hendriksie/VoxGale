# cost-indicator Specification

## Purpose
Make the cost of transcription visible before and during use, and accurate afterwards, so users who pay for their own Mistral API key are never surprised by a bill.

## Requirements

### Requirement: Show estimated cost during a live session
The system SHALL display elapsed session minutes and the estimated cost so far during a live session, using the configured per-minute rate for the realtime model.

#### Scenario: Session running
- **WHEN** a live session has been running for some minutes
- **THEN** the UI shows elapsed minutes and the estimated cost accumulated so far, updating as the session runs

### Requirement: Show estimated cost for file transcription
The system SHALL show the estimated cost of a file transcription before or while it runs, based on the file's duration and the selected model's per-minute rate.

#### Scenario: File transcription starts
- **WHEN** a file transcription starts
- **THEN** the estimated cost for the file is visible before the result arrives

### Requirement: Show actual usage after each session and transcription
The system SHALL display the actual billed audio duration reported by the API and the resulting actual cost after each live session and file transcription.

#### Scenario: Session ends
- **WHEN** a live session ends and the API reports usage
- **THEN** the actual audio duration and actual cost are shown alongside the estimate

### Requirement: Include the post-session diarization pass in cost visibility
The system SHALL show the additional estimated cost of the post-session diarization pass before it runs, and the pass SHALL be skippable.

#### Scenario: Session ends with post-pass pending
- **WHEN** a live session ends and the post-session diarization pass is pending
- **THEN** the UI shows the pass's estimated cost and lets the user run or skip it

### Requirement: Keep displayed rates in one configured place
The system SHALL take displayed per-minute rates from a single configuration source that names each model and its rate, so cost displays cannot silently disagree with each other.

#### Scenario: Rate displayed
- **WHEN** any cost estimate is displayed
- **THEN** the rate used matches the configured rate for the model actually used
