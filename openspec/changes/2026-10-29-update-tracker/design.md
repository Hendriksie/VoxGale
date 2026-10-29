# Design

## Context

VoxGale is a Flutter/Android app distributed as sideloaded APKs from GitHub
Releases (`Hendriksie/VoxGale`, releases published on `v*` tags by the
release workflow — see the `release-distribution` spec). The app version
lives in `pubspec.yaml` (`version: 1.2.0+3`) and flows into the Android
`versionName` at build time. Existing conventions to follow: layered code
behind interfaces (`lib/mistral/` for API clients, `lib/storage/` for Drift
repositories), Riverpod 3.4 providers wired in `session_providers.dart`,
Material 3 dialogs as in `settings_screen.dart` (orange `FilledButton` for
the primary action), mocktail tests with the live API layer mocked. The
motivation and scope are in `proposal.md`; the behavior contract is in
`specs/update-tracker/spec.md`.

## Goals / Non-Goals

**Goals:**

- A silent, throttled background check of the GitHub Releases API at app
  start; a once-per-version Material 3 dialog when a newer release exists;
  the dialog's primary action opens that release's GitHub page in the
  browser.
- A manual "Check for updates" action in the settings screen that runs an
  immediate check and reports the outcome (dialog, up-to-date
  confirmation, or error with retry).
- Everything behind seams so unit/widget tests never touch platform
  channels or the network.

**Non-Goals:**

- No download, no install, no signature verification of artifacts, no
  delta APKs (the in-app updater stays parked in `docs/ideas.md`).
- No spec changes to `release-distribution`, `settings`, or
  `privacy-policy` (the check sends no user data and is not telemetry;
  the settings screen gains a section without violating any of its
  requirements).
- No changes to the mic capture / foreground-service path.

## Decisions

1. **New `lib/update/` layer, mirroring `lib/mistral/`.** The update client
   is a different external system than the Mistral API, so it gets its own
   layer with the same shape: a `UpdateCheckClient` interface, a dio
   implementation, and pinned constants (repo slug `Hendriksie/VoxGale`,
   tag scheme `v<semver>`, 24-hour throttle). Alternatives rejected: putting
   it in `lib/mistral/` (that layer is scoped to Mistral API code by hard
   constraint) and putting it in `lib/app/` (the app layer is UI; the
   client must stay UI-agnostic and mockable).
2. **GitHub Releases is the version source of truth**, via the
   `releases/latest` endpoint, whose `tag_name` and `html_url` are used
   verbatim. This matches the `release-distribution` spec (releases are
   named after `v*` tags with the APK attached). Alternatives rejected:
   reading `CHANGELOG.md` or `pubspec.yaml` from the repo (not authoritative
   for what is actually published).
3. **Installed version via `package_info_plus`.** It reads the platform
   `versionName`, which the Flutter tool injects from `pubspec.yaml` at
   build time — no second version constant to drift. Alternatives rejected:
   hardcoding a version constant (drifts from pubspec) and `--dart-define`
   (would complicate the release workflow).
4. **Opening the release page via `url_launcher`.** Alternatives rejected:
   `share_plus` (already a dependency, but it shares content — it is not
   "open in browser") and a hand-written platform channel (url_launcher is
   the standard, tiny package).
5. **HTTP via dio (already a dependency)** with explicit
   connect/receive timeouts — dio has no default timeouts (project gotcha),
   and the client must pass `BaseOptions` with the `baseUrl` (a bare `Dio()`
   drops it — project gotcha).
6. **Check state in Drift**, as a new single-row `update_state` table
   (`id` `'default'`, `last_check_at_ms` integer, `last_notified_version`
   text), schemaVersion 2 → 3 with a `createTable` migration. The
   timestamp is stored as epoch milliseconds, not a Drift `DateTime`
   (DateTime round-trip loses zone and sub-millisecond precision — project
   gotcha). Alternatives rejected: extending the `preferences` table (that
   table holds the user's transcription preferences; update state is
   app-internal) and adding `shared_preferences` (not a dependency; Drift
   is the local-storage convention).
7. **Throttling: one check per 24 hours, and only a well-formed response
   advances the persisted timestamp.** Alternatives rejected: advancing the
   timestamp on attempt (a user who is offline at every start would never
   be checked) and no throttle at all (GitHub's unauthenticated limit is 60
   requests/hour per IP; the check must also be cheap on battery and
   network).
8. **Once-per-version popup: any dismissal records the version as
   notified.** Alternatives rejected: "Later" snoozing only per app run
   (nags on every start until the user updates) and a separate "skip this
   version" action (more UI for little value).
9. **The dialog is not shown while a live session is recording.** The
   controller reads the live session state before presenting; the version
   is not marked notified in that case, so a later start shows it.
   Alternative rejected: always show (a dialog over an active recording is
   disruptive).
10. **Presentation from the home screen.** An `UpdateCheckController`
    Notifier plus providers in `lib/update/update_providers.dart`; the home
    screen starts the check on first build and observes the result with
    `ref.listen`, showing a Material 3 `AlertDialog` ("Update available",
    body naming both versions, `TextButton` "Later", orange `FilledButton`
    "Open release") matching the settings screen's dialog patterns. State
    mutations invalidate the relevant providers (Riverpod `FutureProvider`
    caches its result forever — project gotcha).
11. **Seams for platform channels.** `AppVersionReader` and `UrlOpener`
    interfaces; production implementations wrap `package_info_plus` and
    `url_launcher`; tests use fakes (platform channels throw or hang in
    widget tests — project gotcha).
12. **The check runs in all build modes**, debug included — dogfooding the
    tracker on dev builds is useful and the throttle bounds the cost.
    Alternative rejected: gating on `kDebugMode`.
13. **Silent failure everywhere.** The controller catches all errors from
    the network, parsing, and storage layers and surfaces nothing; the
    check is ambient, so an error would be noise.
14. **Manual check action: an "Updates" section on the settings screen.**
    It shows the installed version and a "Check for updates" button,
    disabled with a progress indicator while a check runs — mirroring the
    API-key section's patterns (progress + info text). Alternatives
    rejected: routing the action through `SettingsController` (mixes the
    transcription-settings concern with the update concern; the settings
    screen watches the update controller directly) and a separate screen
    (overkill for one action).
15. **The manual check bypasses the 24-hour throttle** (explicit user
    intent) and advances the persisted last-check time on a well-formed
    response; the automatic start check keeps its throttle. Alternative
    rejected: throttling the manual action too (defeats its purpose).
16. **Manual-check outcomes.** Update available → the same dialog as the
    automatic popup, shown even if that version was already notified and
    regardless of the recording gate (explicit intent); up to date → an
    inline "You're up to date" confirmation; failure → the settings
    screen's existing `ErrorBanner` taxonomy (`FailureKind.noNetwork`
    with a retry action), matching how key-validation failures surface.

## Risks / Trade-offs

- **[GitHub unauthenticated rate limit (60 req/h per IP)]** → the 24-hour
  throttle makes this ~1 request/day/install; on shared IPs the limit could
  still trip → silent failure and retry on the next start; no user impact.
- **[Repo rename or tag-scheme change breaks the check]** → the tag fails
  to parse and is ignored silently → the repo slug and tag scheme are
  pinned in one constants file, and the `release-distribution` spec already
  mandates `v*` tags.
- **[Sideload downgrade across the schema bump]** → Drift refuses to open a
  newer database from an older app → downgrades are not a supported path
  (the README documents installing updates over an existing copy); accepted.
- **[Version mismatch if a build overrides `--build-name`]** → the
  comparison uses the platform-reported version; the release workflow
  builds from `pubspec.yaml` without overrides → accepted.
- **["Open release" fails (no browser)]** → the dialog stays usable and the
  app does not crash (spec scenario); `url_launcher`'s own manifest covers
  Android 11+ package visibility, and `INTERNET` is already declared, so no
  manifest change is needed.
- **[Repeated "Check for updates" taps]** → each tap is one request and
  GitHub's unauthenticated limit is 60 requests/hour → the button is
  disabled while a check runs, bounding requests by user patience; the
  limit is not realistically reachable.

## Migration Plan

- Drift schemaVersion 2 → 3: `migration` gains `if (from < 3)
  await migrator.createTable(updateState);` — additive only, no data
  migration. Regenerate `app_database.g.dart` with
  `dart run build_runner build --delete-conflicting-outputs`.
- Rollback: install the previous APK; the only persistent effect is the
  additive table (see the downgrade risk above).

## Open Questions

- The 24-hour throttle is a pinned constant; if dogfooding shows users want
  fresher checks, it can be tuned without any spec change.
- When the full in-app updater is later promoted from `docs/ideas.md`, it
  should reuse this layer (client interface, version comparison, persisted
  state) and only add the download/install flow on top.
