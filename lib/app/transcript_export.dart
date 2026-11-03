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

/// Shares an agent reply via the share sheet (agent-integration spec, change
/// 2026-10-29-send-transcript-to-agent). A provider so widget tests can
/// record it instead of touching the platform channel.
final agentReplyShareProvider = Provider<Future<void> Function(String reply)>(
  (ref) => shareAgentReply,
);

/// The share intent's text extra rides in the binder transaction, which is
/// capped at ~1 MB and carries strings as UTF-16 (~2 bytes per code unit).
/// An export whose text would exceed 500 KB on the wire is shared as the
/// file only, so a very long transcript cannot make the whole share intent
/// fail (change share-transcript-text-extra, design D3).
const int maxShareTextExtraWireBytes = 500 * 1024;

/// Builds the share params for an export: the export text itself (Android
/// `EXTRA_TEXT`) plus the export file (`EXTRA_STREAM`), labelled
/// `text/plain`, so text-consuming share targets (chat and note apps) receive
/// the content as well as file-consuming targets. The file's MIME type is
/// set explicitly — the Markdown export would otherwise go out as
/// `text/markdown`, which text/plain-only targets do not match (design D2).
/// The text extra is omitted when it would exceed
/// [maxShareTextExtraWireBytes] on the wire (design D3).
ShareParams shareParamsForExport(String content, XFile file) => ShareParams(
  text: content.length * 2 <= maxShareTextExtraWireBytes ? content : null,
  files: [XFile(file.path, mimeType: 'text/plain')],
);

/// Writes [reply] to a temp file and opens the system share sheet. The temp
/// file goes to the system temp directory (on Android the app's cache dir),
/// so no platform channel is needed; the share step is injectable for tests.
Future<void> shareAgentReply(
  String reply, {
  Future<ShareResult> Function(ShareParams params)? share,
}) async {
  final file = File(
    '${Directory.systemTemp.path}/voxgale-agent-reply-'
    '${DateTime.now().millisecondsSinceEpoch}.txt',
  );
  await file.writeAsString(reply);
  await (share ?? SharePlus.instance.share)(
    shareParamsForExport(reply, XFile(file.path)),
  );
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
    shareParamsForExport(content, XFile(file.path)),
  );
}
