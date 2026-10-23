/// Single source of truth for pinned Mistral model IDs and per-minute rates.
///
/// Model IDs are pinned to full Voxtral 3 IDs (never `-latest` aliases, which
/// Mistral can silently move to newer versions) and the same source feeds the
/// cost indicator, so model selection and cost display cannot disagree.
/// See design.md decisions D3 and D7.
class MistralConfig {
  const MistralConfig({
    required this.realtimeModel,
    required this.batchMiniModel,
    required this.batchSmallModel,
    required this.realtimeRatePerMinute,
    required this.batchMiniRatePerMinute,
    required this.batchSmallRatePerMinute,
  });

  /// Realtime (WebSocket) transcription model.
  final String realtimeModel;

  /// Batch (REST) transcription model — cheaper, supports every offline feature.
  final String batchMiniModel;

  /// Batch (REST) transcription model — flagship transcription and diarization.
  final String batchSmallModel;

  /// Standard-tier price per minute of audio, USD.
  final double realtimeRatePerMinute;
  final double batchMiniRatePerMinute;
  final double batchSmallRatePerMinute;

  /// Pinned Voxtral 3 IDs and standard-tier rates (verified 2026-10-21 against
  /// the Mistral pricing page; Realtime 3 and Small 3 are Public Preview).
  static const MistralConfig defaults = MistralConfig(
    realtimeModel: 'voxtral-mini-transcribe-realtime-3-0',
    batchMiniModel: 'voxtral-mini-transcribe-3-0',
    batchSmallModel: 'voxtral-small-transcribe-3-0',
    realtimeRatePerMinute: 0.008,
    batchMiniRatePerMinute: 0.0035,
    batchSmallRatePerMinute: 0.004,
  );

  /// The configured per-minute rate for [model].
  ///
  /// Throws [ArgumentError] for a model that is not pinned in this config, so a
  /// cost display can never silently fall back to a wrong rate.
  double rateForModel(String model) {
    if (model == realtimeModel) {
      return realtimeRatePerMinute;
    }
    if (model == batchMiniModel) {
      return batchMiniRatePerMinute;
    }
    if (model == batchSmallModel) {
      return batchSmallRatePerMinute;
    }
    throw ArgumentError('No pinned rate for model: $model');
  }
}
