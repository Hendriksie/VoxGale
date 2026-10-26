// Formatting helpers shared by the app screens: session lengths, USD costs
// (costs are sub-cent per minute, so mill precision), dates, and model
// labels.

import '../mistral/mistral.dart';

/// Formats a session length as `m:ss` (or `h:mm:ss` past an hour).
String formatElapsed(int seconds) {
  final duration = Duration(seconds: seconds);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final secs = duration.inSeconds.remainder(60);
  final mm = minutes.toString().padLeft(2, '0');
  final ss = secs.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$minutes:$ss';
}

/// Formats a USD cost with mill precision (costs are sub-cent per minute).
String formatCost(double value) => '\$${value.toStringAsFixed(3)}';

/// Formats a timestamp as `yyyy-MM-dd HH:mm` (history lists and headers).
String formatDateTime(DateTime time) {
  final date =
      '${time.year.toString().padLeft(4, '0')}-'
      '${time.month.toString().padLeft(2, '0')}-'
      '${time.day.toString().padLeft(2, '0')}';
  final hh = time.hour.toString().padLeft(2, '0');
  final mm = time.minute.toString().padLeft(2, '0');
  return '$date $hh:$mm';
}

/// A short, user-presentable label for a model id (history entries): the
/// realtime model, or Mini/Small for the batch models.
String modelLabel(String model, MistralConfig config) {
  if (model == config.realtimeModel) {
    return 'Realtime';
  }
  if (model == config.batchMiniModel) {
    return 'Mini';
  }
  if (model == config.batchSmallModel) {
    return 'Small';
  }
  return model;
}
