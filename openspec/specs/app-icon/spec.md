# app-icon Specification

## Purpose
Give the app a recognizable launcher icon in the Mistral brand orange, so it stands out on the home screen and in the app drawer and matches the in-app theming.

## Requirements

### Requirement: Use the Mistral-orange launcher icon at every density
The system SHALL use a launcher icon built on the Mistral orange (#FF7000) brand mark at every Android density bucket (mdpi through xxxhdpi), replacing the default framework icon.

#### Scenario: App viewed on the home screen
- **WHEN** the app is installed and viewed on the home screen or in the app drawer
- **THEN** the launcher icon shows the Mistral-orange brand mark at the correct density for the device

### Requirement: Provide an adaptive icon on Android 8 and newer
The system SHALL provide an adaptive icon (foreground and background layers) for Android 8.0 (API 26) and newer, so the system can mask the icon to the device's shape while the brand mark stays centered and legible.

#### Scenario: Adaptive icon on API 26+
- **WHEN** the app runs on Android 8.0 or newer
- **THEN** the launcher uses the adaptive icon with the orange brand mark as the foreground over a solid brand background

### Requirement: Keep the icon legible at small sizes
The system SHALL use a simplified glyph that remains recognizable at the smallest launcher size, without fine detail that disappears when scaled down or masked.

#### Scenario: Icon rendered at the smallest density
- **WHEN** the icon is rendered at mdpi size or masked by the launcher
- **THEN** the brand mark is still recognizable and is not clipped by the mask or the safe zone
