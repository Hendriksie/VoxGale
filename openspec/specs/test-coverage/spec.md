# test-coverage Specification

## Purpose
Protect the app's Mistral client layer and the live transcription flow with automated tests that mock every external service, so regressions are caught without cost, flakiness, or ever hitting the live API.

## Requirements

### Requirement: Unit-test the realtime WebSocket client with a mocked transport
The system SHALL have unit tests for the realtime transcription client that replace the WebSocket transport with a mock, covering session setup, audio chunk sending, event parsing, and error mapping.

#### Scenario: Client behavior changes
- **WHEN** the realtime client's behavior changes
- **THEN** unit tests exercise the changed paths against the mocked transport and fail if the contract breaks

#### Scenario: Stream reports an error
- **WHEN** the realtime stream reports an error event
- **THEN** a unit test verifies the client surfaces the mapped, sanitized error

### Requirement: Unit-test the batch REST client with a mocked transport
The system SHALL have unit tests for the batch transcription client that replace the HTTP layer with a mock, covering the multipart upload, diarization parameters, request timeouts, and error mapping for authentication, quota, and file-limit failures.

#### Scenario: Batch request parameters
- **WHEN** a file transcription request is built
- **THEN** a unit test verifies the request carries the model, diarization, and language parameters the flow selected

#### Scenario: Batch API rejects the file
- **WHEN** the batch API rejects a file (size, duration, authentication, or quota)
- **THEN** a unit test verifies the client surfaces the correct error kind without retrying non-retryable failures

### Requirement: Integration-test the live flow end to end
The system SHALL have an integration test that drives the complete live flow — start a session, receive streaming text, stop, and verify the finalized session is saved to history — over fake Mistral clients and storage, without any real network call.

#### Scenario: Live flow completes
- **WHEN** the integration test drives start → streaming text → stop
- **THEN** the transcript reflects the streamed text and the finalized session appears in history

#### Scenario: Live flow fails mid-session
- **WHEN** the integration test drives a session whose stream fails mid-way
- **THEN** the text received so far is preserved and an error state is surfaced

### Requirement: Never hit the live API from tests
The system SHALL NOT make network requests to the Mistral API from any automated test; every external boundary (WebSocket, HTTP, platform channels) SHALL be mocked or faked in tests.

#### Scenario: Test suite runs
- **WHEN** the automated test suite runs (unit, widget, and integration tests)
- **THEN** no test opens a connection to the Mistral API, and any test that would is replaced with a mock or fake
