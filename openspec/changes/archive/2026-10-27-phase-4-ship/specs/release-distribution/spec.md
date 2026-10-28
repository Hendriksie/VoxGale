# Spec Delta

## Purpose

Ship the app as signed, versioned, installable release artifacts — built reproducibly from a tag and published with the APK attached — so users can install and update it without the developer's machine, and so release artifacts carry no debug surface.

## ADDED Requirements

### Requirement: Sign release builds with a release key
The system SHALL produce release APKs signed with a release key whose keystore and properties are configured outside version control, with the version name and code taken from the app's version declaration, and SHALL NOT sign release builds with a debug key.

#### Scenario: Release build produced
- **WHEN** a release APK is built
- **THEN** the APK verifies against the release key and carries the version name and code from the app's version declaration

#### Scenario: Release key not configured
- **WHEN** a release build runs on a machine without the signing key configured
- **THEN** the build fails with a clear message naming the missing configuration, and no unsigned or debug-signed artifact is produced

### Requirement: Keep the signing key out of version control
The repository SHALL NOT contain the release keystore or its properties file, SHALL ignore them, and SHALL document how to back up the keystore so a lost key never blocks updates to installed copies.

#### Scenario: Fresh clone
- **WHEN** the repository is cloned on a new machine
- **THEN** no keystore or key properties file is present, and the project documentation explains how to generate or restore the key before building a release

### Requirement: Publish versioned releases with the APK attached
Pushing a version tag SHALL publish a release named after the tag with the release APK attached as a downloadable asset, and the same release SHALL be creatable manually with the same artifact when automation is unavailable.

#### Scenario: Version tag pushed
- **WHEN** a version tag is pushed
- **THEN** a release named after the tag exists with the release APK attached, built from that tag

#### Scenario: Automation unavailable
- **WHEN** a release is created manually
- **THEN** the documented manual steps produce a release with the same name and APK artifact as the automated path

### Requirement: Ship release artifacts without debug surface
A release APK SHALL NOT contain debug-only screens or menu entry points, and SHALL NOT bundle debug or spike audio assets.

#### Scenario: Release APK inspected
- **WHEN** a release APK is inspected
- **THEN** its bundled assets contain no debug audio files and the installed app offers no debug menu

### Requirement: Document installation and updates
The project documentation SHALL explain how to install the release APK on a device, what the app does and costs to run, and how to install an update over an existing copy.

#### Scenario: New user installs the app
- **WHEN** a user follows the installation instructions
- **THEN** the release APK installs on their device, and a later release installs over the previous one without uninstalling
