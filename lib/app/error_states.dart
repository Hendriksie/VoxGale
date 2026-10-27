// The shared empty/error-state system (design P3-D1, the empty-error-states
// spec): one failure taxonomy — [FailureKind] mapped to an icon, a
// plain-language message, and a remedy action label ([presentFailure]) — plus
// the widgets every screen renders it through: the full-screen [ErrorStateView]
// for blocking failures that end a flow (errorContainer/onErrorContainer), the
// inline [ErrorBanner] for transient errors (tertiaryContainer — the live
// screen's slim warning-row look), and the [EmptyStateView] for empty content.
//
// [classifyFailure] maps the app's existing error types into the taxonomy:
// the capture service's [CaptureStartFailure] subtypes, [MistralApiException],
// and the controllers' error strings. Messages are sanitized on render — a
// failure whose detail carries key-like material shows only the kind's
// canonical wording, never the raw text (the API key never reaches the UI).

import 'package:flutter/material.dart';

import '../mistral/mistral.dart';
import '../session/capture_service.dart';
import 'theme.dart';

/// The kinds of failure the app distinguishes in its error states
/// (empty-error-states spec: missing preconditions and API failure kinds).
enum FailureKind {
  /// No API key is saved.
  missingKey,

  /// The RECORD_AUDIO runtime permission was denied.
  micPermissionDenied,

  /// No network connection.
  noNetwork,

  /// The API rejected the key (authentication failure).
  auth,

  /// The API quota is exhausted or billing is not set up.
  quota,

  /// Any other failure.
  generic,
}

/// The user-facing presentation of a [FailureKind]: the icon, the canonical
/// plain-language message, and the remedy action's label (null when the kind
/// has no remedy).
class FailurePresentation {
  const FailurePresentation({
    required this.kind,
    required this.icon,
    required this.message,
    this.remedyLabel,
  });

  /// The failure kind.
  final FailureKind kind;

  /// The icon shown with the message.
  final IconData icon;

  /// The canonical, sanitized message (never contains the API key).
  final String message;

  /// The remedy action's label, or null when the kind has no remedy.
  final String? remedyLabel;
}

/// The failure-kind → wording/remedy mapping (design P3-D1): the single place
/// an error state's icon, message, and remedy label come from.
const Map<FailureKind, FailurePresentation> _presentations = {
  FailureKind.missingKey: FailurePresentation(
    kind: FailureKind.missingKey,
    icon: Icons.vpn_key_off,
    message: 'No API key saved. Add your Mistral API key in Settings.',
    remedyLabel: 'Open settings',
  ),
  FailureKind.micPermissionDenied: FailurePresentation(
    kind: FailureKind.micPermissionDenied,
    icon: Icons.mic_off,
    message: 'Microphone permission denied. Grant it to record a session.',
    remedyLabel: 'Grant microphone access',
  ),
  FailureKind.noNetwork: FailurePresentation(
    kind: FailureKind.noNetwork,
    icon: Icons.wifi_off,
    message: 'No network connection. Check your connection and try again.',
    remedyLabel: 'Retry',
  ),
  FailureKind.auth: FailurePresentation(
    kind: FailureKind.auth,
    icon: Icons.lock_outline,
    message: 'The API key was rejected. Check the key in Settings and try again.',
    remedyLabel: 'Open settings',
  ),
  FailureKind.quota: FailurePresentation(
    kind: FailureKind.quota,
    icon: Icons.account_balance_wallet_outlined,
    message: 'Your API quota is exhausted or billing is not set up. '
        'Check your Mistral plan and try again.',
    remedyLabel: 'Retry',
  ),
  FailureKind.generic: FailurePresentation(
    kind: FailureKind.generic,
    icon: Icons.error_outline,
    message: 'Something went wrong. Try again.',
    remedyLabel: 'Retry',
  ),
};

/// The presentation of [kind] — its icon, canonical message, and remedy label.
FailurePresentation presentFailure(FailureKind kind) => _presentations[kind]!;

/// Key-like material (a Mistral API key or a bearer token). Anything matching
/// this pattern is never rendered (empty-error-states spec: no credentials in
/// user-visible error text).
final RegExp _keyLikePattern = RegExp(
  r'sk-[A-Za-z0-9_-]{8,}|bearer\s+[A-Za-z0-9._~+/=-]{8,}',
  caseSensitive: false,
);

/// Whether [text] carries key-like material (an API key or a bearer token).
bool hasKeyLikeMaterial(String text) => _keyLikePattern.hasMatch(text);

/// The user-visible text for a failure message: [raw] when it is present and
/// safe, otherwise [fallback] — the kind's canonical sanitized wording. A raw
/// text carrying key-like material is dropped entirely, never redacted into
/// the message.
String sanitizeFailureText(String? raw, {required String fallback}) {
  if (raw == null || raw.trim().isEmpty || hasKeyLikeMaterial(raw)) {
    return fallback;
  }
  return raw;
}

/// Maps an app failure into the [FailureKind] taxonomy: the capture service's
/// [CaptureStartFailure] subtypes, [MistralApiException], and the controllers'
/// error strings. A detail carrying key-like material is never classified by
/// its content — it is a generic failure, and only the sanitized canonical
/// wording is shown for it.
FailureKind classifyFailure(Object? error) {
  if (error is MicPermissionDenied) {
    return FailureKind.micPermissionDenied;
  }
  final String text;
  if (error == null || error is CaptureStartFailure) {
    // NotificationPermissionDenied / ServiceStartFailed have no dedicated
    // kind — they surface as generic failures.
    text = '';
  } else if (error is MistralApiException) {
    text = error.message;
  } else if (error is String) {
    text = error;
  } else {
    text = error.toString();
  }
  if (text.isEmpty || hasKeyLikeMaterial(text)) {
    return FailureKind.generic;
  }
  final lower = text.toLowerCase();
  if (lower.contains('no api key')) {
    return FailureKind.missingKey;
  }
  if (lower.contains('microphone permission') || lower.contains('mic permission')) {
    return FailureKind.micPermissionDenied;
  }
  if (RegExp(
    'unauthorized|forbidden|authentication|rejected|invalid api key|'
    'invalid key|401|403',
  ).hasMatch(lower)) {
    return FailureKind.auth;
  }
  if (RegExp('quota|billing|payment required|rate limit|429').hasMatch(lower)) {
    return FailureKind.quota;
  }
  if (RegExp(
    'network|timeout|timed out|unreachable|could not reach|cannot reach|'
    'connection|socket|offline|no internet|dns',
  ).hasMatch(lower)) {
    return FailureKind.noNetwork;
  }
  return FailureKind.generic;
}

/// The full-screen blocking failure state (empty-error-states spec): a
/// centered errorContainer card with the failure kind's icon, a plain-language
/// message, and the remedy action (Mistral orange CTA) when the screen
/// provides one. [message] overrides the kind's canonical wording; it is
/// dropped (the canonical sanitized wording shows) when it is empty or
/// carries key-like material.
class ErrorStateView extends StatelessWidget {
  const ErrorStateView({
    super.key,
    required this.kind,
    this.message,
    this.onRemedy,
  });

  /// The failure kind to present.
  final FailureKind kind;

  /// The message to show, or null for the kind's canonical wording.
  final String? message;

  /// The remedy action; the button shows only when both this and the kind's
  /// remedy label are present.
  final VoidCallback? onRemedy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final presentation = presentFailure(kind);
    final text = sanitizeFailureText(message, fallback: presentation.message);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Material(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  presentation.icon,
                  size: 48,
                  color: scheme.onErrorContainer,
                ),
                const SizedBox(height: 16),
                Text(
                  text,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (onRemedy != null && presentation.remedyLabel != null) ...[
                  const SizedBox(height: 24),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: mistralOrange,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: onRemedy,
                    child: Text(presentation.remedyLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The inline transient failure banner (empty-error-states spec): a slim
/// tertiaryContainer row with the failure kind's icon, the message, and an
/// optional remedy action — the live screen's warning-row look, used wherever
/// a non-fatal error surfaces without ending the flow.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({
    super.key,
    required this.kind,
    this.message,
    this.onRemedy,
  });

  /// The failure kind to present.
  final FailureKind kind;

  /// The message to show, or null for the kind's canonical wording.
  final String? message;

  /// The remedy action; the button shows only when both this and the kind's
  /// remedy label are present.
  final VoidCallback? onRemedy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final presentation = presentFailure(kind);
    final text = sanitizeFailureText(message, fallback: presentation.message);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                presentation.icon,
                color: scheme.onTertiaryContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onTertiaryContainer,
                      ),
                    ),
                    if (onRemedy != null && presentation.remedyLabel != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: TextButton(
                          onPressed: onRemedy,
                          child: Text(presentation.remedyLabel!),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The empty-content state (empty-error-states spec): an icon, guidance, and
/// an optional primary action (Mistral orange CTA) — used wherever a screen's
/// content can be empty (the idle live transcript, the empty history, the
/// idle file mode). Neutral styling: an empty state is not an error.
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.icon,
    required this.message,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  /// The icon shown above the message.
  final IconData icon;

  /// The guidance message.
  final String message;

  /// An optional secondary line under the message.
  final String? subtitle;

  /// The primary action's label; the button shows only when both this and
  /// [onAction] are present.
  final String? actionLabel;

  /// The primary action.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 56,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: mistralOrange,
                  foregroundColor: Colors.black,
                ),
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
