import 'dart:convert';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:voxtral_live/mistral/mistral.dart';
import 'package:voxtral_live/session/capture_service.dart';
import 'package:voxtral_live/session/capture_task_handler.dart';
import 'package:voxtral_live/session/session_models.dart';

class MockForegroundTaskGateway extends Mock implements ForegroundTaskGateway {}

void main() {
  setUpAll(() {
    registerFallbackValue(CaptureCommand.stop);
    registerFallbackValue((Object _) {});
  });

  late MockForegroundTaskGateway gateway;
  late CaptureService service;
  void Function(Object)? eventCallback;

  void stubEventCallbackRegistration() {
    when(() => gateway.addEventCallback(any())).thenAnswer((invocation) {
      eventCallback =
          invocation.positionalArguments[0] as void Function(Object);
    });
    when(() => gateway.removeEventCallback(any())).thenAnswer((_) {});
  }

  void verifyServiceNeverStarted() {
    verifyNever(() => gateway.startService(
          notificationTitle: any(named: 'notificationTitle'),
          notificationText: any(named: 'notificationText'),
          notificationButtons: any(named: 'notificationButtons'),
        ));
  }

  setUp(() {
    gateway = MockForegroundTaskGateway();
    stubEventCallbackRegistration();
    service = CaptureService(gateway: gateway, forceStopDelay: Duration.zero);
  });

  group('startSession', () {
    test('checks permissions, saves the config with the session id, and '
        'starts the service with the polished notification', () async {
      when(() => gateway.requestRecordAudioPermission())
          .thenAnswer((_) async => true);
      when(() => gateway.requestNotificationPermission())
          .thenAnswer((_) async => true);
      String? savedConfig;
      when(() => gateway.saveConfig(any())).thenAnswer((invocation) async {
        savedConfig = invocation.positionalArguments[0] as String;
      });
      String? title;
      String? text;
      List<NotificationButton>? buttons;
      when(() => gateway.startService(
            notificationTitle: any(named: 'notificationTitle'),
            notificationText: any(named: 'notificationText'),
            notificationButtons: any(named: 'notificationButtons'),
          )).thenAnswer((invocation) async {
        title = invocation.namedArguments[#notificationTitle] as String;
        text = invocation.namedArguments[#notificationText] as String;
        buttons = invocation.namedArguments[#notificationButtons]
            as List<NotificationButton>;
        return const ServiceRequestSuccess();
      });

      final failure = await service.startSession(
        sessionId: 'session-1',
        config: RealtimeSessionConfig(
          turnDetection: const TurnDetectionConfig(),
        ),
      );

      expect(failure, isNull);
      // The config the service isolate reads: session id + session settings
      // (the settings lock after the first audio chunk).
      final saved = jsonDecode(savedConfig!) as Map<String, dynamic>;
      expect(saved['session_id'], 'session-1');
      expect(saved['session'], isA<Map>());
      expect(
        (saved['session'] as Map)['turn_detection'],
        isA<Map>(),
      );
      // The polished notification: app name, elapsed-time text, stop button.
      expect(title, CaptureService.notificationTitle);
      expect(text, startsWith('Transcribing'));
      expect(buttons, isNotNull);
      expect(buttons!.single.id, CaptureTaskHandler.stopButtonId);
      expect(buttons!.single.text, 'Stop');
    });

    test('fails when the microphone permission is denied', () async {
      when(() => gateway.requestRecordAudioPermission())
          .thenAnswer((_) async => false);
      final failure = await service.startSession(
        sessionId: 'session-1',
        config: RealtimeSessionConfig(),
      );
      expect(failure, isA<MicPermissionDenied>());
      verifyNever(() => gateway.saveConfig(any()));
      verifyServiceNeverStarted();
    });

    test('fails when the notification permission is denied', () async {
      when(() => gateway.requestRecordAudioPermission())
          .thenAnswer((_) async => true);
      when(() => gateway.requestNotificationPermission())
          .thenAnswer((_) async => false);
      final failure = await service.startSession(
        sessionId: 'session-1',
        config: RealtimeSessionConfig(),
      );
      expect(failure, isA<NotificationPermissionDenied>());
      verifyNever(() => gateway.saveConfig(any()));
      verifyServiceNeverStarted();
    });

    test('reports a service start failure', () async {
      when(() => gateway.requestRecordAudioPermission())
          .thenAnswer((_) async => true);
      when(() => gateway.requestNotificationPermission())
          .thenAnswer((_) async => true);
      when(() => gateway.saveConfig(any())).thenAnswer((_) async {});
      when(() => gateway.startService(
            notificationTitle: any(named: 'notificationTitle'),
            notificationText: any(named: 'notificationText'),
            notificationButtons: any(named: 'notificationButtons'),
          )).thenAnswer(
        (_) async => const ServiceRequestFailure(error: 'boom'),
      );
      final failure = await service.startSession(
        sessionId: 'session-1',
        config: RealtimeSessionConfig(),
      );
      expect(failure, isA<ServiceStartFailed>());
      expect((failure as ServiceStartFailed).error, 'boom');
    });
  });

  group('commands', () {
    test('pause and resume send the matching command', () {
      service.pause();
      verify(() => gateway.sendCommand(CaptureCommand.pause)).called(1);
      service.resume();
      verify(() => gateway.sendCommand(CaptureCommand.resume)).called(1);
    });

    test('stop sends the stop command and force-stops a stuck service',
        () async {
      when(() => gateway.isServiceRunning()).thenAnswer((_) async => true);
      var stopServiceCalls = 0;
      when(() => gateway.stopService()).thenAnswer((_) async {
        stopServiceCalls++;
        return const ServiceRequestSuccess();
      });
      await service.stop();
      verify(() => gateway.sendCommand(CaptureCommand.stop)).called(1);
      expect(stopServiceCalls, 1);
    });

    test('stop does not force-stop a service that ended gracefully',
        () async {
      when(() => gateway.isServiceRunning()).thenAnswer((_) async => false);
      await service.stop();
      verify(() => gateway.sendCommand(CaptureCommand.stop)).called(1);
      verifyNever(() => gateway.stopService());
    });
  });

  group('events', () {
    test('payloads from the service are decoded into typed session events',
        () async {
      final events = <SessionEvent>[];
      final sub = service.events.listen(events.add);
      eventCallback!(jsonEncode(const SessionTextDelta('hi').toJson()));
      eventCallback!(jsonEncode(const SessionError('boom').toJson()));
      // Junk payloads are ignored.
      eventCallback!('not json');
      eventCallback!(42);
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(2));
      expect(events[0].toJson(), const SessionTextDelta('hi').toJson());
      expect(events[1].toJson(), const SessionError('boom').toJson());
      await sub.cancel();
    });

    test('the event callback is registered on construction and removed on '
        'dispose', () {
      verify(() => gateway.addEventCallback(any())).called(1);
      service.dispose();
      verify(() => gateway.removeEventCallback(any())).called(1);
    });
  });

  group('battery sanity check', () {
    test('delegates the battery-optimization check and prompt', () async {
      when(() => gateway.isBatteryOptimizationIgnored())
          .thenAnswer((_) async => false);
      expect(await service.isBatteryOptimizationIgnored(), isFalse);
      when(() => gateway.requestIgnoreBatteryOptimization())
          .thenAnswer((_) async => true);
      expect(await service.requestIgnoreBatteryOptimization(), isTrue);
      when(() => gateway.openBatteryOptimizationSettings())
          .thenAnswer((_) async => true);
      expect(await service.openBatteryOptimizationSettings(), isTrue);
    });
  });

  test('isRunning delegates to the gateway', () async {
    when(() => gateway.isServiceRunning()).thenAnswer((_) async => true);
    expect(await service.isRunning(), isTrue);
  });

  test('newSessionId generates unique timestamp-based ids', () {
    final a = CaptureService.newSessionId();
    final b = CaptureService.newSessionId();
    expect(a, startsWith('session-'));
    expect(b, startsWith('session-'));
    expect(a, isNot(b));
  });
}
