# Spec Delta

## Purpose

Let users of sideloaded VoxGale builds learn, inside the app, that a newer
GitHub Release exists, and open that release's page to download it — without
the app downloading or installing anything itself.

## ADDED Requirements

### Requirement: Check for a newer release on app start
The system SHALL check for a newer release when the app starts, at most once
per 24 hours per install, by querying the app's GitHub Releases for the
latest release. The check SHALL run in the background without blocking the
UI, and SHALL fail silently — no error, dialog, or retry prompt — when the
network, the API, or the response is unavailable or malformed. Only a
well-formed response SHALL advance the persisted last-check time, so a
failed check is retried on the next app start.

#### Scenario: App started after the throttle window
- **WHEN** the app starts more than 24 hours after the last well-formed check
- **THEN** a request for the latest release is made

#### Scenario: App started within the throttle window
- **WHEN** the app starts less than 24 hours after the last well-formed check
- **THEN** no request is made

#### Scenario: Network unavailable at app start
- **WHEN** the app starts and the releases API cannot be reached
- **THEN** no user-facing error or dialog is shown, the persisted last-check time is unchanged, and the next app start retries

#### Scenario: Response is malformed
- **WHEN** the releases API responds without a usable version tag
- **THEN** the response is treated as a failed check: no user-facing error, and the last-check time is unchanged

### Requirement: Compare release versions semantically
The system SHALL interpret the latest release's tag as a `v`-prefixed
semantic version (`vMAJOR.MINOR.PATCH`) and SHALL consider an update
available exactly when that version is strictly greater than the installed
app's version. A tag that is not a `v`-prefixed semantic version SHALL be
ignored — no update, no error.

#### Scenario: Newer minor release exists
- **WHEN** the installed version is 1.2.0 and the latest release tag is `v1.3.0`
- **THEN** an update is available

#### Scenario: Newer patch release exists
- **WHEN** the installed version is 1.2.0 and the latest release tag is `v1.2.1`
- **THEN** an update is available

#### Scenario: Installed version is the latest
- **WHEN** the installed version is 1.2.0 and the latest release tag is `v1.2.0`
- **THEN** no update is available

#### Scenario: Tag is not a semantic version
- **WHEN** the latest release tag is not a `v`-prefixed semantic version (for example `nightly`)
- **THEN** the tag is ignored: no update, no error, no dialog

### Requirement: Show the update dialog once per version
When an update is available and the available version has not been notified
yet, the system SHALL show a dialog at app start naming the available
version and the installed version, offering a primary action to open the
release page and a dismiss action. Dismissing the dialog by either action
SHALL record the available version as notified. The dialog SHALL NOT be
shown again for the same version, and SHALL NOT be shown while a live
transcription session is recording.

#### Scenario: Update available and not yet notified
- **WHEN** an update is available and the available version has not been notified
- **THEN** a dialog is shown naming the available version and the installed version

#### Scenario: Dialog dismissed
- **WHEN** the update dialog is dismissed by either action
- **THEN** the available version is recorded as notified and the dialog is not shown again on later app starts for that version

#### Scenario: Update available but already notified
- **WHEN** an update is available and the available version was already notified
- **THEN** no dialog is shown

#### Scenario: No update available
- **WHEN** the installed version is the latest release
- **THEN** no dialog is shown

#### Scenario: Live session recording when the check completes
- **WHEN** an update is available but a live transcription session is recording
- **THEN** no dialog is shown at that app start; the version is not recorded as notified, so a later app start shows it

### Requirement: Offer a manual check-for-updates action in Settings
The system SHALL provide a "Check for updates" action in the app's settings
screen. Tapping it SHALL run an immediate check for a newer release,
bypassing the 24-hour throttle, and a well-formed response SHALL advance
the persisted last-check time.

#### Scenario: User taps "Check for updates"
- **WHEN** the user taps "Check for updates" in the settings screen
- **THEN** an immediate check runs even within the 24-hour throttle window, and a well-formed response advances the persisted last-check time

#### Scenario: A check is already running
- **WHEN** the user taps "Check for updates" while a check is already running
- **THEN** the action is disabled and no second check is started

### Requirement: Report the outcome of a manual check
The system SHALL show the update dialog when a manual check finds a newer
version — including when that version was already notified and while a
live session is recording, because the check was explicitly requested —
and SHALL show an up-to-date confirmation when the installed version is
the latest. When a manual check fails, the system SHALL show an error
with a retry action.

#### Scenario: Manual check finds a newer version
- **WHEN** the user manually checks, a newer version is available, and that version was already notified
- **THEN** the update dialog is shown

#### Scenario: Manual check while a session is recording
- **WHEN** the user manually checks while a live transcription session is recording and a newer version is available
- **THEN** the update dialog is shown (the explicit request overrides the recording gate)

#### Scenario: Manual check with the installed version current
- **WHEN** the user manually checks and the installed version is the latest release
- **THEN** an up-to-date confirmation is shown and no dialog appears

#### Scenario: Manual check fails
- **WHEN** the user manually checks and the releases API cannot be reached
- **THEN** an error with a retry action is shown and no dialog appears

### Requirement: Open the release page in the browser
The system's primary dialog action SHALL open the GitHub release page of the
available version in the device's browser, using the release page URL
reported by the GitHub Releases API for that release.

#### Scenario: User opens the release
- **WHEN** the user taps the dialog's primary action
- **THEN** the device's browser opens the release page URL reported by the API for the available version

#### Scenario: No browser can open the URL
- **WHEN** the user taps the primary action but no browser can open the URL
- **THEN** the app does not crash and the dialog remains usable

### Requirement: Send no credentials or user data with the update check
The update check SHALL send no API key, credential, account identifier, or
user data to GitHub; the check SHALL be an unauthenticated read of the
public releases API.

#### Scenario: Check request is made
- **WHEN** the update check contacts GitHub
- **THEN** the request carries no authorization header and no API key, and only the public releases endpoint is contacted

### Requirement: Persist update-check state across restarts
The system SHALL persist the time of the last well-formed check and the
last notified version in local storage, so both survive an app restart.

#### Scenario: Restart within the throttle window
- **WHEN** the app restarts less than 24 hours after a well-formed check
- **THEN** no new request is made

#### Scenario: Restart after the dialog was dismissed
- **WHEN** the app restarts after the update dialog was dismissed for a version
- **THEN** the dialog is not shown again for that version
