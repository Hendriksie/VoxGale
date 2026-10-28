// Tests for the shared empty/error-state system (design P3-D1, the
// empty-error-states spec, task 2.1): every [FailureKind] renders its mapped
// icon, message, and remedy action through [ErrorStateView] and [ErrorBanner]
// in both themes; [classifyFailure] maps the app's existing error types
// (capture-start failures, [MistralApiException], the controllers' error
// strings) into the taxonomy; and a failure whose detail carries key-like
// material renders only the sanitized canonical text — never the key.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxgale/app/error_states.dart';
import 'package:voxgale/app/theme.dart';
import 'package:voxgale/mistral/mistral.dart';
import 'package:voxgale/session/capture_service.dart';

void main() {
  /// Pumps [child] under [theme] (the app's light/dark theme builders).
  Future<void> pumpThemed(
    WidgetTester tester,
    Widget child,
    ThemeData theme,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: theme, home: Scaffold(body: child)),
    );
    await tester.pump();
  }

  Future<void> unpump(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  group('ErrorStateView (blocking, full-screen)', () {
    for (final kind in FailureKind.values) {
      testWidgets('renders ${kind.name}: icon, message, and remedy action in '
          'both themes', (tester) async {
        final presentation = presentFailure(kind);
        var remedyTaps = 0;
        for (final theme in [buildLightTheme(), buildDarkTheme()]) {
          await pumpThemed(
            tester,
            ErrorStateView(kind: kind, onRemedy: () => remedyTaps++),
            theme,
          );

          expect(find.byType(ErrorStateView), findsOneWidget);
          expect(find.byIcon(presentation.icon), findsOneWidget);
          expect(find.text(presentation.message), findsOneWidget);
          expect(find.text(presentation.remedyLabel!), findsOneWidget);

          await tester.tap(find.text(presentation.remedyLabel!));
          await tester.pump();
          expect(remedyTaps, 1);
          remedyTaps = 0;

          await unpump(tester);
        }
      });
    }

    testWidgets('uses the error container colors (blocking failure)',
        (tester) async {
      await pumpThemed(
        tester,
        const ErrorStateView(kind: FailureKind.generic),
        buildLightTheme(),
      );

      final context = tester.element(find.byType(ErrorStateView));
      final scheme = Theme.of(context).colorScheme;
      final material = tester.widget<Material>(
        find.descendant(
          of: find.byType(ErrorStateView),
          matching: find.byType(Material),
        ),
      );
      expect(material.color, scheme.errorContainer);
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byType(ErrorStateView),
          matching: find.byIcon(Icons.error_outline),
        ),
      );
      expect(icon.color, scheme.onErrorContainer);
    });

    testWidgets('hides the remedy action when none is provided', (tester) async {
      await pumpThemed(
        tester,
        const ErrorStateView(kind: FailureKind.generic),
        buildDarkTheme(),
      );

      expect(find.text('Retry'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('shows a safe message override instead of the canonical one',
        (tester) async {
      await pumpThemed(
        tester,
        const ErrorStateView(
          kind: FailureKind.generic,
          message: 'Could not start the capture service: boom',
        ),
        buildLightTheme(),
      );

      expect(
        find.text('Could not start the capture service: boom'),
        findsOneWidget,
      );
      expect(find.text('Something went wrong. Try again.'), findsNothing);
    });
  });

  group('ErrorBanner (transient, inline)', () {
    for (final kind in FailureKind.values) {
      testWidgets('renders ${kind.name}: icon, message, and remedy action in '
          'both themes', (tester) async {
        final presentation = presentFailure(kind);
        var remedyTaps = 0;
        for (final theme in [buildLightTheme(), buildDarkTheme()]) {
          await pumpThemed(
            tester,
            ErrorBanner(kind: kind, onRemedy: () => remedyTaps++),
            theme,
          );

          expect(find.byType(ErrorBanner), findsOneWidget);
          expect(find.byIcon(presentation.icon), findsOneWidget);
          expect(find.text(presentation.message), findsOneWidget);
          expect(find.text(presentation.remedyLabel!), findsOneWidget);

          await tester.tap(find.text(presentation.remedyLabel!));
          await tester.pump();
          expect(remedyTaps, 1);
          remedyTaps = 0;

          await unpump(tester);
        }
      });
    }

    testWidgets('uses the tertiary container colors (transient error)',
        (tester) async {
      await pumpThemed(
        tester,
        const ErrorBanner(kind: FailureKind.noNetwork),
        buildDarkTheme(),
      );

      final context = tester.element(find.byType(ErrorBanner));
      final scheme = Theme.of(context).colorScheme;
      final material = tester.widget<Material>(
        find.descendant(
          of: find.byType(ErrorBanner),
          matching: find.byType(Material),
        ),
      );
      expect(material.color, scheme.tertiaryContainer);
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byType(ErrorBanner),
          matching: find.byIcon(Icons.wifi_off),
        ),
      );
      expect(icon.color, scheme.onTertiaryContainer);
    });

    testWidgets('hides the remedy action when none is provided', (tester) async {
      await pumpThemed(
        tester,
        const ErrorBanner(kind: FailureKind.noNetwork, message: 'Connection lost'),
        buildLightTheme(),
      );

      expect(find.text('Connection lost'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });
  });

  group('EmptyStateView (empty content)', () {
    testWidgets('renders the icon, message, subtitle, and action in both '
        'themes', (tester) async {
      var actionTaps = 0;
      for (final theme in [buildLightTheme(), buildDarkTheme()]) {
        await pumpThemed(
          tester,
          EmptyStateView(
            icon: Icons.audio_file_outlined,
            message: 'Import an audio file',
            subtitle: 'It is transcribed with speaker labels.',
            actionLabel: 'Pick an audio file',
            onAction: () => actionTaps++,
          ),
          theme,
        );

        expect(find.byIcon(Icons.audio_file_outlined), findsOneWidget);
        expect(find.text('Import an audio file'), findsOneWidget);
        expect(find.text('It is transcribed with speaker labels.'),
            findsOneWidget);
        await tester.tap(find.text('Pick an audio file'));
        await tester.pump();
        expect(actionTaps, 1);
        actionTaps = 0;

        await unpump(tester);
      }
    });

    testWidgets('renders without subtitle and action', (tester) async {
      await pumpThemed(
        tester,
        const EmptyStateView(
          icon: Icons.history,
          message: 'No transcripts yet.',
        ),
        buildLightTheme(),
      );

      expect(find.text('No transcripts yet.'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  group('classifyFailure (the failure taxonomy)', () {
    test('maps the capture start failures', () {
      expect(
        classifyFailure(const MicPermissionDenied()),
        FailureKind.micPermissionDenied,
      );
      // The other capture-start failures have no dedicated kind.
      expect(
        classifyFailure(const NotificationPermissionDenied()),
        FailureKind.generic,
      );
      expect(
        classifyFailure(ServiceStartFailed('service exploded')),
        FailureKind.generic,
      );
    });

    test('maps the controllers\' error strings', () {
      expect(
        classifyFailure(
            'No API key saved. Add your Mistral API key to start a session.'),
        FailureKind.missingKey,
      );
      expect(
        classifyFailure(
            'No API key saved. Add your Mistral API key in Settings.'),
        FailureKind.missingKey,
      );
      expect(
        classifyFailure(
            'Microphone permission denied. Grant it to record a session.'),
        FailureKind.micPermissionDenied,
      );
      expect(
        classifyFailure('Notification permission denied. '
            'The capture notification needs it.'),
        FailureKind.generic,
      );
      expect(
        classifyFailure('Could not start the capture service: boom'),
        FailureKind.generic,
      );
      expect(
        classifyFailure('The capture service stopped without saving the '
            'session.'),
        FailureKind.generic,
      );
      expect(
        classifyFailure('Could not save the session: disk full'),
        FailureKind.generic,
      );
      expect(
        classifyFailure('Connection lost'),
        FailureKind.noNetwork,
      );
    });

    test('maps the Mistral API exceptions', () {
      expect(
        classifyFailure(MistralApiException(
            'The API key was rejected. Check the key and try again.')),
        FailureKind.auth,
      );
      expect(
        classifyFailure(MistralApiException(
            'The validation request failed (HTTP 401).')),
        FailureKind.auth,
      );
      expect(
        classifyFailure(
            MistralApiException('Your API quota is exhausted.')),
        FailureKind.quota,
      );
      expect(
        classifyFailure(
            MistralApiException('Transcription API returned an error (429)')),
        FailureKind.quota,
      );
      expect(
        classifyFailure(MistralApiException(
            'Network timeout while calling the transcription API '
            '(receiveTimeout)')),
        FailureKind.noNetwork,
      );
      expect(
        classifyFailure(MistralApiException(
            'Could not reach the Mistral API to validate the key '
            '(connectionError). Try again.')),
        FailureKind.noNetwork,
      );
      expect(
        classifyFailure(
            MistralApiException('Transcription API returned an error (500)')),
        FailureKind.generic,
      );
      expect(
        classifyFailure(
            MistralApiException('The file is too large for the API.')),
        FailureKind.generic,
      );
    });

    test('maps other objects and empty input to generic', () {
      expect(classifyFailure(null), FailureKind.generic);
      expect(classifyFailure(''), FailureKind.generic);
      expect(classifyFailure(StateError('whatever')), FailureKind.generic);
    });

    test('a failure carrying key-like material classifies as generic', () {
      expect(
        classifyFailure(
            MistralApiException('Unauthorized: Bearer sk-abc123def456ghi')),
        FailureKind.generic,
      );
      expect(
        classifyFailure('failed with key sk-abc123def456ghi'),
        FailureKind.generic,
      );
    });
  });

  group('sanitization (no key-like material in user-visible text)', () {
    test('hasKeyLikeMaterial detects keys and bearer tokens', () {
      expect(hasKeyLikeMaterial('key sk-abc123def456 leaked'), isTrue);
      expect(hasKeyLikeMaterial('Authorization: Bearer abc123def456'), isTrue);
      expect(hasKeyLikeMaterial('No API key saved.'), isFalse);
      expect(hasKeyLikeMaterial('The API key was rejected.'), isFalse);
      expect(hasKeyLikeMaterial(''), isFalse);
    });

    test('sanitizeFailureText falls back to the canonical wording', () {
      const fallback = 'Something went wrong. Try again.';
      expect(sanitizeFailureText(null, fallback: fallback), fallback);
      expect(sanitizeFailureText('', fallback: fallback), fallback);
      expect(sanitizeFailureText('   ', fallback: fallback), fallback);
      expect(
        sanitizeFailureText('Bearer sk-abc123def456ghi', fallback: fallback),
        fallback,
      );
      expect(
        sanitizeFailureText('Could not start the capture service: boom',
            fallback: fallback),
        'Could not start the capture service: boom',
      );
    });

    testWidgets('ErrorStateView renders only the sanitized text for a '
        'key-carrying failure', (tester) async {
      await pumpThemed(
        tester,
        const ErrorStateView(
          kind: FailureKind.auth,
          message: 'Unauthorized: Bearer sk-abc123def456ghi',
        ),
        buildLightTheme(),
      );

      // The key-like material never renders; only the canonical wording.
      expect(find.textContaining('sk-abc123def456ghi'), findsNothing);
      expect(find.textContaining('Bearer'), findsNothing);
      expect(
        find.text(presentFailure(FailureKind.auth).message),
        findsOneWidget,
      );
    });

    testWidgets('ErrorBanner renders only the sanitized text for a '
        'key-carrying failure', (tester) async {
      await pumpThemed(
        tester,
        const ErrorBanner(
          kind: FailureKind.generic,
          message: 'failed with key sk-abc123def456ghi',
        ),
        buildDarkTheme(),
      );

      expect(find.textContaining('sk-abc123def456ghi'), findsNothing);
      expect(
        find.text(presentFailure(FailureKind.generic).message),
        findsOneWidget,
      );
    });
  });
}
