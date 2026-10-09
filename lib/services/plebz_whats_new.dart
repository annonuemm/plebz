import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import '../utils/app_logger.dart';
import 'plebz_update_service.dart';

/// Where the notes ship inside the app. The same text, section by section, is
/// the body of the matching GitHub release — written once, before a release.
const plebzWhatsNewAsset = 'assets/whats_new.md';

/// One version's notes: "## 1.2.0 (Build 559)" and the lines under it.
class PlebzWhatsNewEntry {
  const PlebzWhatsNewEntry({required this.version, required this.build, required this.lines});

  final String version;
  final int build;

  /// The section's lines as written: "- " bullets, "### " sub-headings,
  /// paragraphs, blank lines between.
  final List<String> lines;
}

/// The sections of [source], newest first. A heading without a build number
/// ("## Unreleased") and anything above the first heading are left out: a
/// section only shows once it names the build that ships it.
List<PlebzWhatsNewEntry> parsePlebzWhatsNew(String source) {
  final entries = <PlebzWhatsNewEntry>[];
  String? version;
  int? build;
  var lines = <String>[];
  void close() {
    if (version != null && build != null) {
      entries.add(PlebzWhatsNewEntry(version: version, build: build, lines: _trimBlank(lines)));
    }
  }

  for (final raw in source.split('\n')) {
    final line = raw.trimRight();
    if (line.startsWith('## ')) {
      close();
      final heading = line.substring(3).trim();
      build = PlebzUpdateService.buildNumberOf(heading);
      version = heading.split(RegExp(r'\s')).first;
      lines = [];
    } else if (version != null) {
      lines.add(line);
    }
  }
  close();
  entries.sort((a, b) => b.build.compareTo(a.build));
  return entries;
}

List<String> _trimBlank(List<String> lines) {
  var start = 0;
  var end = lines.length;
  while (start < end && lines[start].trim().isEmpty) {
    start++;
  }
  while (end > start && lines[end - 1].trim().isEmpty) {
    end--;
  }
  return lines.sublist(start, end);
}

/// What changed since [lastSeen] up to and including [current]: every
/// section in between, so an update that skipped a release still tells of it.
/// With nothing seen before (the first start of a build that brought these
/// notes), only the newest section at or below [current].
List<PlebzWhatsNewEntry> plebzWhatsNewSince(
  List<PlebzWhatsNewEntry> entries, {
  required int lastSeen,
  required int current,
}) {
  final upToCurrent = [
    for (final entry in entries)
      if (entry.build <= current) entry,
  ];
  if (lastSeen <= 0) return upToCurrent.take(1).toList();
  return [
    for (final entry in upToCurrent)
      if (entry.build > lastSeen) entry,
  ];
}

/// The notes shipped with this build; empty when the file is missing or
/// unreadable — the notes are an extra, never a reason for an error.
Future<List<PlebzWhatsNewEntry>> loadPlebzWhatsNew({AssetBundle? bundle}) async {
  try {
    return parsePlebzWhatsNew(await (bundle ?? rootBundle).loadString(plebzWhatsNewAsset));
  } catch (error) {
    appLogger.d('Plebz: no notes to show', error: error);
    return const [];
  }
}

/// [entries] as text for the scrollable dialog: each version as a bold line,
/// then its notes. [lead] comes first, as its own paragraph.
TextSpan plebzWhatsNewSpan(List<PlebzWhatsNewEntry> entries, {String? lead}) {
  final children = <InlineSpan>[];
  if (lead != null) children.add(TextSpan(text: lead));
  for (final entry in entries) {
    if (children.isNotEmpty) children.add(const TextSpan(text: '\n\n'));
    children.add(
      TextSpan(
        // The version alone: the build number orders the sections and is not
        // for the reader (the viewer's call).
        text: 'Plebz ${entry.version}',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
    final notes = plebzNotesSpan(entry.lines.join('\n'));
    if (notes.children?.isNotEmpty ?? false) {
      children
        ..add(const TextSpan(text: '\n'))
        ..add(notes);
    }
  }
  return TextSpan(children: children);
}

/// One section's notes — or a GitHub release body, written the same way — as
/// text: "- " bullets become "•", "### " sub-headings and **words** bold,
/// runs of blank lines one break.
TextSpan plebzNotesSpan(String notes, {String? lead}) {
  final children = <InlineSpan>[];
  if (lead != null) children.add(TextSpan(text: lead));
  var gap = lead != null;
  for (final raw in notes.replaceAll('\r\n', '\n').split('\n')) {
    final line = raw.trimRight();
    if (line.trim().isEmpty) {
      gap = children.isNotEmpty;
      continue;
    }
    if (children.isNotEmpty) children.add(TextSpan(text: gap ? '\n\n' : '\n'));
    gap = false;
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('#')) {
      children.add(
        TextSpan(
          text: trimmed.replaceFirst(RegExp(r'^#+\s*'), ''),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );
    } else if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
      final indent = line.length - trimmed.length >= 2 ? '      ' : '';
      children
        ..add(TextSpan(text: '$indent•  '))
        ..addAll(_inline(trimmed.substring(2).trim()));
    } else {
      children.addAll(_inline(trimmed));
    }
  }
  return TextSpan(children: children);
}

/// "**bold**" inside a line; everything else as it stands.
List<InlineSpan> _inline(String text) {
  final spans = <InlineSpan>[];
  final bold = RegExp(r'\*\*(.+?)\*\*');
  var at = 0;
  for (final match in bold.allMatches(text)) {
    if (match.start > at) spans.add(TextSpan(text: text.substring(at, match.start)));
    spans.add(
      TextSpan(
        text: match.group(1),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
    at = match.end;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return spans;
}
