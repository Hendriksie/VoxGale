# privacy-policy Specification

## Purpose
Tell users plainly what the app records, where their audio and transcripts go, and how their data is deleted — in a privacy policy that ships with the project and stays linked from the README.

## Requirements

### Requirement: Publish a privacy policy at a stable location
The repository SHALL contain a privacy policy document at a stable path, and the project README SHALL link to it.

#### Scenario: User looks for the policy
- **WHEN** a user opens the project repository or the README
- **THEN** a privacy policy is present at the stable path and reachable from the README

### Requirement: State what is recorded and where it goes
The privacy policy SHALL state, in plain language, that the app records microphone audio; that audio and transcripts are sent to the Mistral API under the user's own API key over an encrypted connection; that the API key is stored in the device's secure storage and sent only to Mistral; and that transcripts and session audio are stored locally on the device.

#### Scenario: User reads the policy
- **WHEN** a user reads the privacy policy
- **THEN** the recording, the transmission to Mistral, the key storage, and the local storage of audio and transcripts are each stated plainly

### Requirement: State what the app does not do
The privacy policy SHALL state that the app creates no accounts, syncs no data to a cloud service, and sends no analytics, telemetry, or crash reports from the device.

#### Scenario: User checks for hidden data collection
- **WHEN** a user reads the privacy policy looking for data collection
- **THEN** the policy states that there are no accounts, no cloud sync, and no telemetry or crash reporting

### Requirement: Explain how data is deleted
The privacy policy SHALL state how a user deletes their data: deleting individual transcripts or all history within the app, and that uninstalling the app removes all of its data from the device.

#### Scenario: User wants their data gone
- **WHEN** a user reads the deletion section
- **THEN** the in-app deletion options and the effect of uninstalling are both stated
