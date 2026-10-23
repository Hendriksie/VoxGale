// UI-side wrapper around the capture foreground service (design P1-D1, task
// 3.2): permission checks, the battery sanity check, service start with the
// polished notification (elapsed time + stop action), the command channel,
// and the typed event stream. The UI isolate never captures.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:record/record.dart';

import '../mistral/mistral.dart';
import 'capture_task_handler.dart';
import 'session_models.dart';

/// The flutter_foreground_task surface the capture service wrapper needs,
/// behind an interface so unit tests can mock the plugin (the plugin's
/// statics are platform channels — they cannot run in a unit test).
abstract interface class ForegroundTaskGateway {
  /// Requests the RECORD_AUDIO runtime permission. Returns whether it is
  /// granted.
  Future<bool> requestRecordAudioPermission();

  /// Requests the POST_NOTIFICATIONS runtime permission (Android 13+).
  /// Returns whether it is granted.
  Future<bool> requestNotificationPermission();

  /// Whether the app is exempt from battery optimization.
  Future<bool> isBatteryOptimizationIgnored();

  /// Prompts the user to exempt the app from battery optimization (the
  /// battery sanity check's prompt — the prompt UI itself is group 5).
  Future<bool> requestIgnoreBatteryOptimization();

  /// Opens the system battery-optimization settings for the app.
  Future<bool> openBatteryOptimizationSettings();

  /// Whether the capture service is currently running.
  Future<bool> isServiceRunning();

  /// Saves the session config for the service isolate to read.
  Future<void> saveConfig(String configJson);

  /// Starts the capture service (microphone type) with the given
  /// notification.
  Future<ServiceRequestResult> startService({
    required String notificationTitle,
    required String notificationText,
    required List<NotificationButton> notificationButtons,
  });

  /// Sends a command to the service isolate.
  void sendCommand(CaptureCommand command);

  /// Stops the service (the force-stop fallback).
  Future<ServiceRequestResult> stopService();

  /// Registers/unregisters the callback for data sent from the service
  /// isolate.
  void addEventCallback(void Function(Object data) callback);
  void removeEventCallback(void Function(Object data) callback);
}

/// [ForegroundTaskGateway] delegating to the flutter_foreground_task statics.
class PluginForegroundTaskGateway implements ForegroundTaskGateway {
  @override
  Future<bool> requestRecordAudioPermission() async {
    // record requests the RECORD_AUDIO runtime permission natively. (record's
    // dispose throws if the recorder was never created — swallow it.)
    final recorder = AudioRecorder();
    final granted = await recorder.hasPermission();
    try {
      await recorder.dispose();
    } catch (_) {}
    return granted;
  }

  @override
  Future<bool> requestNotificationPermission() async {
    // Android 13+ requires POST_NOTIFICATIONS, or the foreground-service
    // notification is silently suppressed (the service still runs, but no
    // notification shows — observed on device).
    final permission = await FlutterForegroundTask.requestNotificationPermission();
    return permission == NotificationPermission.granted;
  }

  @override
  Future<bool> isBatteryOptimizationIgnored() =>
      FlutterForegroundTask.isIgnoringBatteryOptimizations;

  @override
  Future<bool> requestIgnoreBatteryOptimization() =>
      FlutterForegroundTask.requestIgnoreBatteryOptimization();

  @override
  Future<bool> openBatteryOptimizationSettings() =>
      FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();

  @override
  Future<bool> isServiceRunning() => FlutterForegroundTask.isRunningService;

  @override
  Future<void> saveConfig(String configJson) async {
    await FlutterForegroundTask.saveData(
      key: CaptureTaskHandler.configKey,
      value: configJson,
    );
  }

  @override
  Future<ServiceRequestResult> startService({
    required String notificationTitle,
    required String notificationText,
    required List<NotificationButton> notificationButtons,
  }) =>
      FlutterForegroundTask.startService(
        serviceId: 256,
        serviceTypes: [ForegroundServiceTypes.microphone],
        notificationTitle: notificationTitle,
        notificationText: notificationText,
        notificationButtons: notificationButtons,
        callback: captureBackgroundTaskHandler,
      );

  @override
  void sendCommand(CaptureCommand command) =>
      FlutterForegroundTask.sendDataToTask(command.wireValue);

  @override
  Future<ServiceRequestResult> stopService() =>
      FlutterForegroundTask.stopService();

  @override
  void addEventCallback(void Function(Object data) callback) =>
      FlutterForegroundTask.addTaskDataCallback(callback);

  @override
  void removeEventCallback(void Function(Object data) callback) =>
      FlutterForegroundTask.removeTaskDataCallback(callback);
}

/// Why [CaptureService.startSession] did not start a session.
sealed class CaptureStartFailure {
  const CaptureStartFailure();
}

/// The RECORD_AUDIO runtime permission was not granted.
final class MicPermissionDenied extends CaptureStartFailure {
  const MicPermissionDenied();
}

/// The POST_NOTIFICATIONS runtime permission was not granted.
final class NotificationPermissionDenied extends CaptureStartFailure {
  const NotificationPermissionDenied();
}

/// The foreground service itself failed to start.
final class ServiceStartFailed extends CaptureStartFailure {
  const ServiceStartFailed(this.error);

  final Object error;
}

/// UI-side handle on the capture foreground service (design P1-D1): starts
/// and stops the service, sends commands (pause/resume/stop), and exposes the
/// session events forwarded from the service isolate as a typed stream.
class CaptureService {
  CaptureService({
    ForegroundTaskGateway? gateway,
    this.forceStopDelay = const Duration(seconds: 2),
  })  : _gateway = gateway ?? PluginForegroundTaskGateway() {
    _gateway.addEventCallback(_onTaskData);
  }

  /// Notification title: the app name (spec: persistent notification).
  static const String notificationTitle = 'Voxtral Live';

  /// How long [stop] waits for the graceful stop before force-stopping the
  /// service (the spike's fallback for a stuck graceful path).
  final Duration forceStopDelay;

  /// The notification stop button. Its id must match
  /// [CaptureTaskHandler.stopButtonId] — the tap is delivered to the handler
  /// in the service isolate.
  static const List<NotificationButton> _notificationButtons = [
    NotificationButton(id: CaptureTaskHandler.stopButtonId, text: 'Stop'),
  ];

  final ForegroundTaskGateway _gateway;
  final StreamController<SessionEvent> _events =
      StreamController<SessionEvent>.broadcast();

  /// Session events forwarded from the capture service isolate. Broadcast,
  /// no replay: subscribe before [startSession]. Closed by [dispose].
  Stream<SessionEvent> get events => _events.stream;

  /// Generates a session id (timestamp-based, unique per app run). Also the
  /// file name of the session audio and the identity carried by the final
  /// session-ended event.
  static String newSessionId() =>
      'session-${DateTime.now().millisecondsSinceEpoch}-${_sessionIdCounter++}';

  static int _sessionIdCounter = 0;

  /// Whether the capture service is currently running.
  Future<bool> isRunning() => _gateway.isServiceRunning();

  /// Whether the app is exempt from battery optimization (spec: battery
  /// sanity check). When false, the UI should prompt the user — group 5
  /// builds the prompt.
  Future<bool> isBatteryOptimizationIgnored() =>
      _gateway.isBatteryOptimizationIgnored();

  /// Prompts the user to allow unrestricted background activity.
  Future<bool> requestIgnoreBatteryOptimization() =>
      _gateway.requestIgnoreBatteryOptimization();

  /// Opens the system battery settings so the user can exempt the app.
  Future<bool> openBatteryOptimizationSettings() =>
      _gateway.openBatteryOptimizationSettings();

  /// Starts a capture session: checks the runtime permissions, saves the
  /// config (session id + session settings — the settings lock after the
  /// first audio chunk) for the service isolate, and starts the service with
  /// the polished notification. Returns null on success, or why it did not
  /// start.
  Future<CaptureStartFailure?> startSession({
    required String sessionId,
    required RealtimeSessionConfig config,
  }) async {
    // The runtime permissions must be granted before the service starts.
    if (!await _gateway.requestRecordAudioPermission()) {
      return const MicPermissionDenied();
    }
    if (!await _gateway.requestNotificationPermission()) {
      return const NotificationPermissionDenied();
    }

    // The session config is fixed at start (settings lock), so it is saved
    // for the service isolate to read, together with the session id (the WAV
    // file name and the final event's session identity).
    await _gateway.saveConfig(jsonEncode({
      'session_id': sessionId,
      'session': config.toSessionUpdateJson(),
    }));

    final result = await _gateway.startService(
      notificationTitle: notificationTitle,
      notificationText: 'Transcribing · 00:00',
      notificationButtons: _notificationButtons,
    );
    return switch (result) {
      ServiceRequestSuccess() => null,
      ServiceRequestFailure(:final error) => ServiceStartFailed(error),
    };
  }

  /// Pauses capture and transcription; the realtime session stays open
  /// (design P1-D2).
  void pause() => _gateway.sendCommand(CaptureCommand.pause);

  /// Resumes a paused session.
  void resume() => _gateway.sendCommand(CaptureCommand.resume);

  /// Stops the session: graceful first — the service ends the realtime
  /// session, closes the WAV, forwards the final session-ended event, and
  /// stops itself; if the service is still running after [forceStopDelay]
  /// (the graceful path is stuck), it is force-stopped.
  Future<void> stop() async {
    _gateway.sendCommand(CaptureCommand.stop);
    await Future<void>.delayed(forceStopDelay);
    if (await _gateway.isServiceRunning()) {
      await _gateway.stopService();
    }
  }

  /// Unregisters the event callback and closes the event stream. Does not
  /// stop a running session.
  void dispose() {
    _gateway.removeEventCallback(_onTaskData);
    _events.close();
  }

  void _onTaskData(Object data) {
    final event = SessionEvent.fromWire(data);
    if (event != null) {
      _events.add(event);
    }
  }
}
