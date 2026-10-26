# Tasks

## 1. Dependencies and storage schema (design P2-D3)

- [x] 1.1 Add `file_picker`, `share_plus`, and `just_audio` to `pubspec.yaml` with one-line justification comments (proposal Impact); verify `flutter pub get` succeeds.
- [x] 1.2 Bump the Drift schema to v2: add `source` (`live` | `file`) and `sourceFileName` (nullable) columns to `sessions`, create the `Preferences` table, and write the 1→2 migration (existing rows default to `live`); regenerate `app_database.g.dart` with `dart run build_runner build --delete-conflicting-outputs`; verify the generated file is committed and `flutter analyze` is clean.
- [x] 1.3 Extend `SessionRepository` with `listSessions({String? searchQuery})` (newest first; search matches segment text via LIKE over a join) and `deleteAllSessions()` (removes each session's audio file via the existing delete path), with the Drift implementation; verify with repository unit tests on `AppDatabase.memory()` (list order, search filtering, delete-all removes audio files).
- [x] 1.4 Add the `PreferencesRepository` interface (get/save default batch model + language hint) with a Drift implementation and a Riverpod provider; verify with unit tests (round-trip persistence, defaults when nothing is stored).

## 2. Key validation client (design P2-D4)

- [x] 2.1 Add a `KeyValidationClient` interface in `lib/mistral/` whose `validate(apiKey)` takes the candidate key per call (so the settings controller can validate before saving), plus `DioKeyValidationClient` doing a cheap `GET /v1/models` with explicit finite timeouts and sanitized errors (never a key in a message); verify with unit tests on a mocked dio (200 → valid, 401/403 → invalid, unreachable → retryable error, no key leakage in messages).

## 3. Settings screen (design P2-D4)

- [x] 3.1 Implement `SettingsController` (Riverpod notifier): key status (saved/not saved, never the value), save-with-validation (validate → write to `SecureStorageApiKeyStore` only on success; failure leaves the key unsaved with an error and retry), key removal, and preference load/save; verify with unit tests (mocktail fakes for the validator, key store, and preferences repository: invalid key is not saved, network failure is retryable, removal blocks transcription until a new key is saved).
- [x] 3.2 Implement `lib/app/settings_screen.dart`: key status display, key entry with validate/save progress and error states, remove-key action, and default-model + language-hint controls bound to preferences; verify with widget tests (missing-key state, invalid-key error shown, preference changes persist through the fake repository).
- [x] 3.3 Remove the debug-only API key entry tile from `lib/app/debug_hub_screen.dart` (the settings screen replaces it); keep the spike screens; verify `flutter analyze` is clean and the debug hub widget test passes (update it if it referenced the tile).

## 4. File transcription flow (design P2-D1, P2-D2, P2-D5)

- [x] 4.1 Implement `FileTranscriptionController` (Riverpod notifier): pick file (file_picker seam), probe duration (just_audio seam), estimate via `MistralConfig.rateForModel(selectedModel)`, run `BatchTranscriptionClient.transcribe(diarize: true, model, language)`, save to `SessionRepository` with source `file`, the source file name, the model, and the billed usage, and expose the `idle → picked → running → result | error` state machine; verify with unit tests (mocked client/repository: success saves with source + model + usage, API error keeps the picked file and shows an error state, no key → missing-key state).
- [x] 4.2 Give the production implementations of the injected seams direct test coverage — the just_audio duration prober and the ticking clock's production implementation (Phase-1 lesson: fakes hide production-only paths); verify the tests exist and pass.
- [x] 4.3 Implement `lib/app/file_transcription_screen.dart`: entry action → system picker → progress state with elapsed time and the running estimated cost (no partial text — the batch API is one-shot) → speaker-labelled result with actual usage (reusing `transcript_widgets.dart`); verify with widget tests (progress shows elapsed + estimate, result shows segments + actual cost, error state keeps the file).
- [x] 4.4 Wire the file transcription providers (controller, picker/prober seams with production defaults); verify `flutter analyze` is clean and provider-override tests pass.

## 5. History UI, export, and pass re-offer (design P2-D6, P2-D7)

- [x] 5.1 Add a `model` parameter to `DiarizationPass` (defaulting to the batch Mini model) so `estimateCost`/`run` use `config.rateForModel(model)`, and wire both the session-end offer and the new re-offer to the configured default batch model preference; verify the existing pass tests are updated and pass, with new tests covering the Small-model rate.
- [x] 5.2 Implement `lib/app/history_screen.dart`: newest-first list showing date, duration, source (live or file name), and model, plus a search field filtering via `listSessions(searchQuery:)`; verify with widget tests against a fake repository (entries render source/model, search filters the list).
- [x] 5.3 Implement `lib/app/history_detail_screen.dart`: metadata header (date, duration, source/file name, model, actual cost when known), the speaker-labelled transcript via `transcript_widgets.dart`, export and delete actions with confirmation dialogs, and delete-all in the history app bar; verify with widget tests (metadata renders, delete removes the entry, delete-all empties the list).
- [x] 5.4 Add the pass re-offer to the history detail view: shown when the session is `provisional` and its audio file still exists (file-existence check, not just the stored path — a successful pass leaves a stale `audioPath`), with the pass's estimated cost; running it replaces the transcript and deletes the audio on success, failure keeps the provisional transcript with a retry; verify with widget/controller tests (offer shown for a skipped pass with retained audio, hidden when the audio is gone or the session is final).
- [x] 5.5 Implement export as pure text/Markdown builder functions over stored segments (unit-tested for both formats), a temp-file write to the system temp directory (the app cache dir on Android; no platform channel, so the flow is testable off-device), and the `share_plus` share-sheet invocation; verify the builder tests pass, the export widget test covers the sheet + file write, and `flutter analyze` is clean (the share sheet itself is exercised by the device smoke test in 7.3).

## 6. Navigation (design P2-D8)

- [x] 6.1 Add file-mode, history, and settings actions to the live session screen's app bar (imperative `MaterialPageRoute` pushes, matching the existing style); keep the `kDebugMode`-gated debug action; verify with a widget test (actions present, each pushes the right screen).
- [x] 6.2 Show a missing-key state with an open-settings action at the file-mode entry when no API key is saved (settings spec); verify with a widget test.

## 7. Integration checks

- [ ] 7.1 Run `openspec validate --strict` for this change; verify it passes.
- [ ] 7.2 Run `flutter analyze` and the full `flutter test` suite; verify both are clean (tests mock the Mistral layer and never hit the live API).
- [ ] 7.3 Physical-device smoke test (the mic/foreground-service rule does not trigger — this change touches neither — but file picking, the share sheet, and secure storage are platform channels): on a physical Android device, save a key via settings (validation succeeds), import an audio file → transcribe → the result appears in history with its source, export it via the share sheet, and delete it from history (audio removed); verify each step on device and record the results.
- [ ] 7.4 Tick the four Phase 2 milestone items in `project-plan.md`; verify all Phase 2 checkboxes are checked.

## Workflow follow-up

- Review the change (specs + design + tasks) with the user; archive only after tests pass and the review is done.
- Archive the change, which syncs the delta specs into the main specs; verify the archived result with `openspec validate --strict` and `openspec list`.
