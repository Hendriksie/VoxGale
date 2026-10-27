# Spec Delta

## MODIFIED Requirements

### Requirement: Show estimated cost during a live session
The system SHALL display elapsed session minutes and the estimated cost so far during a live session, using the configured per-minute rate for the realtime model. The elapsed time and the estimate SHALL advance only while capture is active; a paused period SHALL NOT add to either.

#### Scenario: Session running
- **WHEN** a live session has been capturing for some minutes
- **THEN** the UI shows elapsed minutes and the estimated cost accumulated so far, updating while the session captures

#### Scenario: Session paused
- **WHEN** a live session is paused
- **THEN** the elapsed time and the estimated cost stay where they were and do not advance until the session resumes
