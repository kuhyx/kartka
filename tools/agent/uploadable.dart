// Judges a Kartka diagnostics log by the app's own upload rule
// (lib/core/diagnostics/upload_rule.dart): prints every entry since
// --since that would reach /kartka/errors, and the kinds kept local.
//
//   fvm dart run tools/agent/uploadable.dart <log.jsonl> [--since <ISO>]
//
// Exit 0: nothing since --since would be uploaded. 1: something would.
// 2: bad usage or unreadable log.
import 'dart:convert';
import 'dart:io';

import 'package:kartka/core/diagnostics/diagnostic_entry.dart';
import 'package:kartka/core/diagnostics/upload_rule.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: uploadable.dart <log.jsonl> [--since <ISO>]');
    exit(2);
  }
  final at = args.indexOf('--since');
  final since = at == -1 ? null : DateTime.parse(args[at + 1]);
  final log = File(args.first);
  if (!log.existsSync()) {
    stderr.writeln('no log at ${log.path}');
    exit(2);
  }
  final local = <String, int>{};
  var up = 0;
  for (final line in log.readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    final e = DiagnosticEntry.fromJson(
      jsonDecode(line) as Map<String, Object?>,
    );
    if (since != null && e.at.isBefore(since)) continue;
    if (isUploadedEntry(e)) {
      up++;
      stdout.writeln('UPLOAD ${e.kind}: ${e.error}');
    } else {
      local[e.kind] = (local[e.kind] ?? 0) + 1;
    }
  }
  stdout
    ..writeln('local: ${jsonEncode(local)}')
    ..writeln('uploaded: $up');
  exit(up == 0 ? 0 : 1);
}
