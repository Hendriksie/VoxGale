// The settings screen's controller (design P2-D4): the API key's status
// (saved/not saved — never the value), save-with-validation (a cheap test
// request before the key is stored; a failure leaves the key unsaved with
// an error and a retry), key removal, and the persisted transcription
// preferences (default batch model, language hint). The key itself is read
// and written only through the [ApiKeyStore] and the [KeyValidationClient]
// interfaces — never displayed, logged, or carried in the state.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mistral/mistral.dart';
import '../storage/storage.dart';
import 'session_providers.dart';

/// The settings screen's state (design P2-D4).
class SettingsState {
  const SettingsState({
    this.loaded = false,
    this.keySaved = false,
    this.validating = false,
    this.error = '',
    this.info = '',
    this.defaultBatchModel,
    this.languageHint,
  });

  /// Whether the initial load (key presence + preferences) has completed.
  final bool loaded;

  /// Whether an API key is saved (the value is never carried here).
  final bool keySaved;

  /// Whether a key validation is in flight.
  final bool validating;

  /// The current error message; empty when there is none.
  final String error;

  /// A transient info message (e.g. "API key saved"); empty when none.
  final String info;

  /// The default batch model id, or null for the pinned Mini default.
  final String? defaultBatchModel;

  /// The pinned language hint, or null for automatic detection.
  final String? languageHint;

  /// Whether [error] carries a message.
  bool get hasError => error.isNotEmpty;

  /// Sentinel for [copyWith]: omit the argument to keep the current value;
  /// pass an explicit null to clear a nullable field.
  static const Object _keep = Object();

  SettingsState copyWith({
    bool? loaded,
    bool? keySaved,
    bool? validating,
    String? error,
    String? info,
    Object? defaultBatchModel = _keep,
    Object? languageHint = _keep,
  }) =>
      SettingsState(
        loaded: loaded ?? this.loaded,
        keySaved: keySaved ?? this.keySaved,
        validating: validating ?? this.validating,
        error: error ?? this.error,
        info: info ?? this.info,
        defaultBatchModel: defaultBatchModel == _keep
            ? this.defaultBatchModel
            : defaultBatchModel as String?,
        languageHint: languageHint == _keep
            ? this.languageHint
            : languageHint as String?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingsState &&
          loaded == other.loaded &&
          keySaved == other.keySaved &&
          validating == other.validating &&
          error == other.error &&
          info == other.info &&
          defaultBatchModel == other.defaultBatchModel &&
          languageHint == other.languageHint;

  @override
  int get hashCode => Object.hash(
        loaded,
        keySaved,
        validating,
        error,
        info,
        defaultBatchModel,
        languageHint,
      );
}

/// The settings controller (design P2-D4): owns [SettingsState].
class SettingsController extends Notifier<SettingsState> {
  @override
  SettingsState build() {
    // Load the key's presence and the stored preferences. The key itself is
    // never read here — only its presence (settings spec).
    unawaited(_load());
    return const SettingsState();
  }

  Future<void> _load() async {
    final key = await ref.read(apiKeyStoreProvider).readKey();
    final preferences =
        await ref.read(preferencesRepositoryProvider).loadPreferences();
    if (!ref.mounted) {
      return;
    }
    state = state.copyWith(
      loaded: true,
      keySaved: key != null && key.isNotEmpty,
      defaultBatchModel: preferences.defaultBatchModel,
      languageHint: preferences.languageHint,
    );
  }

  /// Validates [candidate] with a cheap test request and saves it to secure
  /// storage only when the validation succeeds (settings spec). A failure
  /// leaves the key unsaved with an error the user can retry.
  Future<void> saveKey(String candidate) async {
    final key = candidate.trim();
    if (key.isEmpty || state.validating) {
      return;
    }
    state = state.copyWith(validating: true, error: '', info: '');
    try {
      await ref.read(keyValidationClientProvider).validate(key);
      await ref.read(apiKeyStoreProvider).saveKey(key);
      if (!ref.mounted) {
        return;
      }
      state = state.copyWith(
        validating: false,
        keySaved: true,
        info: 'API key saved.',
      );
      ref.invalidate(apiKeyProvider);
    } on MistralApiException catch (e) {
      if (!ref.mounted) {
        return;
      }
      state = state.copyWith(validating: false, error: e.message);
    } catch (e) {
      if (!ref.mounted) {
        return;
      }
      state = state.copyWith(
        validating: false,
        error: 'Could not validate the API key: $e',
      );
    }
  }

  /// Removes the stored API key (settings spec): no transcription can run
  /// until a new key is saved.
  Future<void> removeKey() async {
    await ref.read(apiKeyStoreProvider).deleteKey();
    if (!ref.mounted) {
      return;
    }
    state = state.copyWith(keySaved: false, info: 'API key removed.');
    ref.invalidate(apiKeyProvider);
  }

  /// Sets the default batch model and persists it (settings spec: applied to
  /// new transcriptions that don't choose a model).
  Future<void> setDefaultBatchModel(String model) async {
    state = state.copyWith(defaultBatchModel: model, info: '');
    await _persistPreferences();
  }

  /// Sets the language hint (null for automatic detection) and persists it.
  Future<void> setLanguageHint(String? hint) async {
    state = state.copyWith(languageHint: hint, info: '');
    await _persistPreferences();
  }

  Future<void> _persistPreferences() async {
    await ref.read(preferencesRepositoryProvider).savePreferences(
          StoredPreferences(
            defaultBatchModel: state.defaultBatchModel,
            languageHint: state.languageHint,
          ),
        );
    ref.invalidate(preferencesProvider);
  }
}
