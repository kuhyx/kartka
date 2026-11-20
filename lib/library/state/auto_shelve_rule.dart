/// The auto-shelving rule (DOCS-spec "Auto-shelving"): which entries are
/// stale and which category each one belongs in. Pure, so it is tested on
/// pinned instants.
library;

import 'dart:math';

import 'package:kartka/core/models/models.dart';

/// Months without a new chapter before an entry is shelved.
const shelveAfterMonths = 18;

/// The two shelves.
enum Shelf {
  /// Every chapter read.
  finished,

  /// Some chapter still unread.
  abandoned,
}

/// The id a shelf category gets when the rule creates it: fixed, so two
/// devices that both create it make one category, not two.
String autoShelfId(Shelf shelf) => 'autoshelve.${shelf.name}';

/// [now] (in UTC) minus [shelveAfterMonths] calendar months; a day the
/// earlier month lacks clamps to its last day (Aug 31 -> Feb 28).
DateTime staleCutoff(DateTime now) {
  final u = now.toUtc();
  final first = DateTime.utc(u.year, u.month - shelveAfterMonths);
  final lastDay = DateTime.utc(first.year, first.month + 1, 0).day;
  return DateTime.utc(
    first.year,
    first.month,
    min(u.day, lastDay),
    u.hour,
    u.minute,
    u.second,
    u.millisecond,
  );
}

/// Whether a newest chapter uploaded at [newest] is older than the cutoff.
bool isStale(DateTime newest, DateTime now) =>
    newest.isBefore(staleCutoff(now));

/// The live category that is [shelf], or `null`: the one with the rule's
/// id, else (lowest order first) `finished` matched whole and
/// case-insensitively, or a name containing `abandon` or `complet`.
Category? shelfCategory(Shelf shelf, List<Category> live) {
  final byOrder = [...live]..sort((a, b) => a.order.compareTo(b.order));
  bool named(Category c) {
    final n = c.name.trim().toLowerCase();
    return switch (shelf) {
      Shelf.finished => n == 'finished',
      Shelf.abandoned => n.contains('abandon') || n.contains('complet'),
    };
  }

  final id = autoShelfId(shelf);
  return byOrder.where((c) => c.id == id).firstOrNull ??
      byOrder.where(named).firstOrNull;
}
