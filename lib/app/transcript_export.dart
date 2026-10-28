// The transcript export (design P2-D6, task 5.5): pure builders over a
// stored session and its segments producing the plain-text and Markdown
// exports, plus the share-sheet invocation. The builders are platform-free
// so they are unit-testable; the share step is exercised by the device smoke
// test (and the widget tests install a mock share platform).

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../mistral/mistral.dart';
import '../storage/storage.dart';
import 'formatters.dart';

/// The export-and-share action (design P2-D6): writes the export and opens
/// the share sheet. A provider so widget tests can record it instead of
/// touching the platform channel.
final transcriptExportProvider = Provider<
    Future<void> Function(
      StoredSessionRecord,
      MistralConfig, {
      required bool markdown,
    })>(
  (ref) => shareTranscriptExport,
);

/// Maps a stored speaker label to its display form (`speaker_1` →
/// `Speaker 1`); enrolled names pass through unchanged.
String speakerLabelForDisplay(String label) {
  final match = RegExp(r'^speaker_(\d+)$').firstMatch(label);
  if (match == null) {
    return label;
  }
  return 'Speaker ${match.group(1)}';
}

/// The export header's source line: a live session, or the imported file.
String _sourceLine(StoredSession session) =>
    session.source == StoredSession.sourceFile
        ? 'File: ${session.sourceFileName ?? 'unknown'}'
        : 'Live session';

/// Builds the plain-text export of a stored transcript (transcript-history
/// spec: export to plain text).
String transcriptToPlainText(
  StoredSession session,
  List<StoredSegment> segments,
  MistralConfig config,
) {
  final lines = <String>[
    'VoxGale transcript',
    '${formatDateTime(session.startedAt)} · '
        '${formatElapsed(session.durationSeconds)} · '
        '${modelLabel(session.model, config)} · ${_sourceLine(session)}',
    '',
    for (final segment in segments) _plainSegmentLine(segment),
  ];
  return lines.join('\n');
}

String _plainSegmentLine(StoredSegment segment) {
  final prefix = <String>[
    if (segment.startSeconds != null)
      '[${formatElapsed(segment.startSeconds!.round())}]',
    if (segment.speakerLabel != null)
      '${speakerLabelForDisplay(segment.speakerLabel!)}:',
  ].join(' ');
  return prefix.isEmpty ? segment.text : '$prefix ${segment.text}';
}

/// Builds the Markdown export of a stored transcript (transcript-history
/// spec: export to Markdown).
String transcriptToMarkdown(
  StoredSession session,
  List<StoredSegment> segments,
  MistralConfig config,
) {
  final lines = <String>[
    '# Transcript — ${formatDateTime(session.startedAt)}',
    '',
    '_${formatElapsed(session.durationSeconds)} · '
        '${modelLabel(session.model, config)} · ${_sourceLine(session)}_',
    '',
    for (var i = 0; i < segments.length; i++) ...[
      if (i > 0) '',
      ..._markdownSegmentLines(segments[i]),
    ],
  ];
  return lines.join('\n');
}

List<String> _markdownSegmentLines(StoredSegment segment) {
  final heading = <String>[
    if (segment.speakerLabel != null)
      '**${speakerLabelForDisplay(segment.speakerLabel!)}**',
    if (segment.startSeconds != null)
      '(${formatElapsed(segment.startSeconds!.round())})',
  ].join(' ');
  return heading.isEmpty ? [segment.text] : [heading, segment.text];
}

/// Writes the export to a temp file and opens the system share sheet
/// (transcript-history spec: export via the share sheet). The temp file goes
/// to the system temp directory — on Android that is the app's cache dir,
/// and unlike `path_provider` it needs no platform channel, so the flow is
/// testable off-device. The share step is injectable ([share]) so tests can
/// record it instead of touching the platform channel.
Future<void> shareTranscriptExport(
  StoredSessionRecord record,
  MistralConfig config, {
  required bool markdown,
  Future<ShareResult> Function(ShareParams params)? share,
}) async {
  final content = markdown
      ? transcriptToMarkdown(record.session, record.segments, config)
      : transcriptToPlainText(record.session, record.segments, config);
  final file = File(
    '${Directory.systemTemp.path}/voxtral-transcript-${record.session.id}'
    '${markdown ? '.md' : '.txt'}',
  );
  await file.writeAsString(content);
  await (share ?? SharePlus.instance.share)(
    ShareParams(files: [XFile(file.path)]),
  );
}
