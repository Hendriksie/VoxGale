// The history search query (transcript-history spec: search transcripts by
// their text content): a small notifier holding the history screen's current
// query, so the list provider re-runs when it changes.

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The history screen's search query (design P2-D6).
class HistorySearchQuery extends Notifier<String> {
  @override
  String build() => '';

  /// Sets the search query.
  void set(String query) => state = query;
}
