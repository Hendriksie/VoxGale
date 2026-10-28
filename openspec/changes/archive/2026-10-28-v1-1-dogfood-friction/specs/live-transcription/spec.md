# Spec Delta

## MODIFIED Requirements

### Requirement: Check background battery restrictions
The system SHALL check whether the app is exempt from battery optimization when a session is about to start or while it is active, and SHALL prompt the user to allow unrestricted background activity when it is not, explaining that capture may otherwise be killed while the screen is off. The system SHALL re-check the exemption when the app returns to the foreground and SHALL dismiss the prompt once the app is exempt, without restarting the app.

#### Scenario: App not exempt from battery optimization
- **WHEN** a session starts and the app is not exempt from battery optimization
- **THEN** the system prompts the user to allow unrestricted background activity, with a way to open the system battery settings

#### Scenario: App already exempt
- **WHEN** a session starts and the app is already exempt from battery optimization
- **THEN** no prompt is shown and the session starts normally

#### Scenario: Exemption granted while the app is backgrounded
- **WHEN** the user grants the exemption in the system battery settings and returns to the app
- **THEN** the prompt is dismissed without restarting the app
