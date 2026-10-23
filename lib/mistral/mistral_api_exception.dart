/// An error from the Mistral API layer.
///
/// The message is always sanitized: it must never contain the user's API key,
/// which lives only in request headers and must never reach logs, crash
/// reports, or the UI.
class MistralApiException implements Exception {
  MistralApiException(this.message);

  final String message;

  @override
  String toString() => 'MistralApiException: $message';

  /// Returns [error]'s string form with [apiKey] redacted.
  ///
  /// Underlying clients (WebSocket, HTTP) can echo request configuration —
  /// including headers — into their error strings, so every error that leaves
  /// this layer passes through here.
  static String sanitize(Object error, String apiKey) {
    final text = error.toString();
    if (apiKey.isEmpty) {
      return text;
    }
    return text.replaceAll(apiKey, '***');
  }
}
