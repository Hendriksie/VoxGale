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

### Requirement: Use the redesigned launcher icon
The system SHALL use the redesigned launcher icon glyph selected by the maintainer from the presented options (recorded in this change's `design.md`), replacing the v1.0 waveform glyph, at every Android density bucket (mdpi through xxxhdpi) and as the adaptive-icon foreground on Android 8.0 and newer, with the vector foreground geometry matching the raster glyphs.

#### Scenario: App viewed on the home screen after the redesign
- **WHEN** the app is installed with the redesigned icon and viewed on the home screen or in the app drawer
- **THEN** the launcher icon shows the redesigned glyph at the correct density for the device

#### Scenario: Adaptive icon on API 26+ after the redesign
- **WHEN** the app runs on Android 8.0 or newer with the redesigned icon
- **THEN** the launcher uses the adaptive icon with the redesigned glyph as the foreground over the solid brand background, legible within the mask safe zone at the smallest density
