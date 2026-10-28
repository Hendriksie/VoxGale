import 'package:flutter_test/flutter_test.dart';
import 'package:voxgale/mistral/mistral_config.dart';

void main() {
  test('exposes the pinned Voxtral 3 model IDs and per-minute rates', () {
    const config = MistralConfig.defaults;

    expect(config.realtimeModel, 'voxtral-mini-transcribe-realtime-3-0');
    expect(config.batchMiniModel, 'voxtral-mini-transcribe-3-0');
    expect(config.batchSmallModel, 'voxtral-small-transcribe-3-0');
    expect(config.realtimeRatePerMinute, 0.008);
    expect(config.batchMiniRatePerMinute, 0.0035);
    expect(config.batchSmallRatePerMinute, 0.004);
  });

  test('rateForModel returns the configured rate for each pinned model', () {
    const config = MistralConfig.defaults;

    expect(config.rateForModel(config.realtimeModel), 0.008);
    expect(config.rateForModel(config.batchMiniModel), 0.0035);
    expect(config.rateForModel(config.batchSmallModel), 0.004);
  });

  test('rateForModel throws for a model that is not pinned', () {
    const config = MistralConfig.defaults;

    expect(
      () => config.rateForModel('voxtral-mini-transcribe-realtime-2602'),
      throwsArgumentError,
    );
  });
}
