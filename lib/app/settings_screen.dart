// The settings screen (design P2-D4, tasks 3.1-3.2): the production API key
// entry — validated with a cheap test request before it is saved, the value
// never displayed — key removal, and the transcription preferences (default
// batch model, language hint). The screen renders [SettingsState] directly
// and owns no logic; every action goes through [SettingsController] — except
// the Updates section (change 2026-10-29-update-tracker, task 6.3, design
// decision 14), which watches the update check controller directly for the
// manual "Check for updates" action.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mistral/mistral.dart';
import '../session/session_providers.dart';
import '../session/settings_controller.dart';
import '../update/update_check_controller.dart';
import '../update/update_providers.dart';
import 'error_states.dart';
import 'theme.dart';

/// The settings screen: the app's production settings (settings spec). It
/// replaces the debug-only API key entry on the debug route.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final config = ref.watch(mistralConfigProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ApiKeySection(state: state, controller: controller),
            const SizedBox(height: 24),
            _PreferencesSection(
              state: state,
              controller: controller,
              config: config,
            ),
            const SizedBox(height: 24),
            const _UpdatesSection(),
          ],
        ),
      ),
    );
  }
}

/// The API key section: saved/not-saved status (never the value), the entry
/// with validation, and removal. Owns its [TextEditingController] so it is
/// disposed with the section, not while it is still animating out.
class _ApiKeySection extends StatefulWidget {
  const _ApiKeySection({required this.state, required this.controller});

  final SettingsState state;
  final SettingsController controller;

  @override
  State<_ApiKeySection> createState() => _ApiKeySectionState();
}

class _ApiKeySectionState extends State<_ApiKeySection> {
  final _keyController = TextEditingController();

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ApiKeySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A successful save empties the field: the typed value is not kept
    // around (the key itself lives in secure storage only).
    if (widget.state.info == 'API key saved.' &&
        widget.state.info != oldWidget.state.info) {
      _keyController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = widget.state;
    final controller = widget.controller;
    // The validation error rendered through the shared taxonomy: an invalid
    // key is an auth failure, an unreachable API a no-network failure (with a
    // retry action — re-validating the entered key).
    final errorKind = state.hasError ? classifyFailure(state.error) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Mistral API key', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        // The key's status only — the value is never displayed (settings
        // spec).
        Row(
          children: [
            Icon(
              state.keySaved ? Icons.vpn_key : Icons.vpn_key_off,
              size: 18,
              color: state.keySaved
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              state.keySaved ? 'Saved' : 'Not saved',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        if (!state.loaded || state.validating) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
        ],
        if (state.validating) ...[
          const SizedBox(height: 8),
          Text(
            'Validating…',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (state.hasError) ...[
          const SizedBox(height: 8),
          ErrorBanner(
            kind: errorKind!,
            message: state.error,
            onRemedy: errorKind == FailureKind.noNetwork
                ? () => controller.saveKey(_keyController.text)
                : null,
          ),
        ],
        if (state.info.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            state.info,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _keyController,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          enabled: state.loaded && !state.validating,
          decoration: const InputDecoration(
            labelText: 'API key',
            hintText: 'sk-…',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (state.keySaved)
              TextButton(
                onPressed: () => _confirmRemove(context, controller),
                child: const Text('Remove key'),
              ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: mistralOrange,
                foregroundColor: Colors.black,
              ),
              onPressed: state.loaded && !state.validating
                  ? () => controller.saveKey(_keyController.text)
                  : null,
              child: const Text('Save key'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    SettingsController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove API key?'),
        content: const Text(
          'No transcription can run until a new key is saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await controller.removeKey();
    }
  }
}

/// The transcription preferences section: the default batch model and the
/// language hint, bound to the persisted preferences (settings spec).
class _PreferencesSection extends StatelessWidget {
  const _PreferencesSection({
    required this.state,
    required this.controller,
    required this.config,
  });

  final SettingsState state;
  final SettingsController controller;
  final MistralConfig config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Transcription preferences', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        Text('Default batch model', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 4),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(
              value: config.batchMiniModel,
              label: const Text('Mini'),
              tooltip: 'Cheaper batch transcription',
            ),
            ButtonSegment(
              value: config.batchSmallModel,
              label: const Text('Small'),
              tooltip: 'Flagship transcription and diarization',
            ),
          ],
          selected: {state.defaultBatchModel ?? config.batchMiniModel},
          onSelectionChanged: state.loaded
              ? (selection) =>
                  controller.setDefaultBatchModel(selection.first)
              : null,
        ),
        const SizedBox(height: 16),
        Text('Language', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 4),
        DropdownButton<String?>(
          value: state.languageHint,
          isExpanded: true,
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Automatic detection'),
            ),
            for (final entry in languageHints.entries)
              DropdownMenuItem<String?>(
                value: entry.key,
                child: Text(entry.value),
              ),
          ],
          onChanged: state.loaded
              ? (value) => controller.setLanguageHint(value)
              : null,
        ),
      ],
    );
  }
}

/// The updates section (change 2026-10-29-update-tracker, tasks 6.3-6.4,
/// design decisions 14-16): the installed version and the manual "Check for
/// updates" action. The section watches [updateCheckControllerProvider]
/// directly — not through [SettingsController] (design decision 14) — and
/// reports the manual check's outcome inline: the up-to-date confirmation, or
/// the shared [ErrorBanner] with a retry action when the check fails (the
/// check fails only when GitHub is unreachable, hence [FailureKind.noNetwork]
/// — design decision 16). When a manual check finds a newer version, the home
/// screen's listener presents the update dialog over this screen (root
/// navigator), so no dialog code lives here.
class _UpdatesSection extends ConsumerWidget {
  const _UpdatesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(updateCheckControllerProvider);
    final controller = ref.read(updateCheckControllerProvider.notifier);
    // The installed version — nothing extra while it loads.
    final version = ref.watch(installedVersionProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Updates', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        version.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (installed) => Text(
            'VoxGale v$installed',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (state.checking) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
        ],
        if (state.outcome == UpdateCheckOutcome.upToDate) ...[
          const SizedBox(height: 8),
          Text(
            "You're up to date.",
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (state.outcome == UpdateCheckOutcome.failed) ...[
          const SizedBox(height: 8),
          ErrorBanner(
            kind: FailureKind.noNetwork,
            message: state.errorMessage,
            onRemedy: () => controller.checkNow(),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: mistralOrange,
                foregroundColor: Colors.black,
              ),
              onPressed: state.checking ? null : () => controller.checkNow(),
              child: const Text('Check for updates'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Common languages for the language-hint dropdown (settings screen). The
/// hint is an ISO 639-1 code; "Automatic detection" stores null.
const Map<String, String> languageHints = {
  'en': 'English',
  'es': 'Spanish',
  'fr': 'French',
  'de': 'German',
  'it': 'Italian',
  'pt': 'Portuguese',
  'nl': 'Dutch',
  'pl': 'Polish',
  'ru': 'Russian',
  'uk': 'Ukrainian',
  'tr': 'Turkish',
  'ar': 'Arabic',
  'hi': 'Hindi',
  'zh': 'Chinese',
  'ja': 'Japanese',
  'ko': 'Korean',
};
