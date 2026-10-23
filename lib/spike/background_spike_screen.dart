import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:record/record.dart';

import '../mistral/mistral.dart';
import 'spike_task_handler.dart';

/// Spike B — background capture (tasks 4.1–4.2).
///
/// Starts the Android foreground service (microphone type) running the live
/// pipeline in its own isolate, and shows the events forwarded from it. The
/// physical-device smoke test (screen off 30+ minutes, airplane-mode
/// reconnect) is run manually with this screen on a real device.
class BackgroundSpikeScreen extends StatefulWidget {
  const BackgroundSpikeScreen({super.key});

  @override
  State<BackgroundSpikeScreen> createState() => _BackgroundSpikeScreenState();
}

class _BackgroundSpikeScreenState extends State<BackgroundSpikeScreen> {
  bool _running = false;
  String? _error;
  final List<String> _log = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    // The service may still be running from a previous visit (navigating away
    // does not stop it) — restore the running state so Stop works.
    _refreshRunning();
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refreshRunning() async {
    final running = await FlutterForegroundTask.isRunningService;
    if (mounted) {
      setState(() => _running = running);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  void _onTaskData(Object data) {
    if (!mounted || data is! String) {
      return;
    }
    final Map<String, dynamic> map;
    try {
      map = jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    setState(() {
      switch (map['type']) {
        case 'text':
          _log.add(map['text'] as String);
        case 'segment':
          _log.add('[${map['speaker']}] ${map['text']}'
              .trim());
        case 'turn':
          _log.add('— turn —');
        case 'status':
          _log.add('[${map['message']}]');
        case 'done':
          _log.add('— done (${map['audioSeconds']}s billed) —');
        case 'error':
          _error = map['message'] as String;
      }
    });
    _scrollToBottom();
    if (map['type'] == 'done' || map['type'] == 'error') {
      _refreshRunning();
    }
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _log.clear();
    });

    // The runtime permission must be granted before the service starts; the
    // recorder requests it natively from the UI isolate. (record's dispose
    // throws if the recorder was never created — swallow it.)
    final recorder = AudioRecorder();
    final granted = await recorder.hasPermission();
    try {
      await recorder.dispose();
    } catch (_) {}
    if (!granted) {
      setState(() => _error = 'Microphone permission denied.');
      return;
    }

    // Android 13+ requires the POST_NOTIFICATIONS runtime permission, or the
    // foreground-service notification is silently suppressed (the service still
    // runs, but no notification shows — observed on device).
    final notificationPermission =
        await FlutterForegroundTask.requestNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      setState(() => _error =
          'Notification permission not granted — the recording notification '
          'will not show. Grant it in Settings → Apps → Voxtral Live → '
          'Notifications, then retry.');
      return;
    }

    // The session config is fixed at start (settings lock), so it is saved
    // for the service isolate to read.
    await FlutterForegroundTask.saveData(
      key: SpikeTaskHandler.configKey,
      value: jsonEncode(RealtimeSessionConfig(
        turnDetection: const TurnDetectionConfig(),
      ).toSessionUpdateJson()),
    );

    final result = await FlutterForegroundTask.startService(
      serviceId: 256,
      serviceTypes: [ForegroundServiceTypes.microphone],
      notificationTitle: 'Voxtral spike',
      notificationText: 'Transcribing in the background',
      callback: spikeBackgroundTaskHandler,
    );

    switch (result) {
      case ServiceRequestSuccess():
        setState(() => _running = true);
      case ServiceRequestFailure(:final error):
        setState(() => _error = 'Could not start the service: $error');
    }
    // Reconcile with the actual service state (e.g. "already started").
    await _refreshRunning();
  }

  Future<void> _stop() async {
    // Single Stop button: graceful first — the task ends the session and
    // stops the service itself. If the service is still running after a
    // short wait (the graceful path is stuck), stop it directly.
    FlutterForegroundTask.sendDataToTask(SpikeTaskHandler.stopCommand);
    await Future<void>.delayed(const Duration(seconds: 2));
    await _refreshRunning();
    if (_running) {
      await FlutterForegroundTask.stopService();
      await _refreshRunning();
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Spike B — background capture')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Runs the live pipeline in a foreground service (microphone '
              'type). On a real device: start, turn the screen off, and watch '
              'the transcript keep growing for 30+ minutes.',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _running ? null : _start,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start background session'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _running ? _stop : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Scrollbar(
                  controller: _scrollController,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    child: SelectableText(
                      _log.isEmpty
                          ? '(transcript events from the service appear here)'
                          : _log.join(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
