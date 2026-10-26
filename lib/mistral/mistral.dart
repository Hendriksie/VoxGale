/// The Mistral API layer.
///
/// Hard constraint: ALL Mistral API code lives in this library behind abstract
/// interfaces (realtime WebSocket + batch REST). UI and foreground-service code
/// must never call the API directly — depend on these interfaces so the layer
/// stays mockable and survives model-ID churn.
library;

export 'api_key_store.dart';
export 'batch/batch_transcription_client.dart';
export 'batch/dio_batch_transcription_client.dart';
export 'key_validation_client.dart';
export 'mistral_api_exception.dart';
export 'mistral_config.dart';
export 'realtime/realtime_events.dart';
export 'realtime/realtime_session_config.dart';
export 'realtime/realtime_transcription_client.dart';
export 'realtime/web_socket_realtime_client.dart';
export 'transcript.dart';
