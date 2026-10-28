# Spec Delta

## ADDED Requirements

### Requirement: Use the redesigned launcher icon
The system SHALL use the redesigned launcher icon glyph selected by the maintainer from the presented options (recorded in this change's `design.md`), replacing the v1.0 waveform glyph, at every Android density bucket (mdpi through xxxhdpi) and as the adaptive-icon foreground on Android 8.0 and newer, with the vector foreground geometry matching the raster glyphs.

#### Scenario: App viewed on the home screen after the redesign
- **WHEN** the app is installed with the redesigned icon and viewed on the home screen or in the app drawer
- **THEN** the launcher icon shows the redesigned glyph at the correct density for the device

#### Scenario: Adaptive icon on API 26+ after the redesign
- **WHEN** the app runs on Android 8.0 or newer with the redesigned icon
- **THEN** the launcher uses the adaptive icon with the redesigned glyph as the foreground over the solid brand background, legible within the mask safe zone at the smallest density
