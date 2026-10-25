/// A [SourceHealthFeed] that re-scores, re-ranks and re-judges the base feed
/// with the active [ScoringProfile], live. The Sources tab and Browse's
/// badges both read it, so they follow the profile together.
library;

import 'dart:async';

import 'package:kartka/source_health/feed/source_health_feed.dart';
import 'package:kartka/source_health/model/source_health_meta.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/scoring/judge.dart';
import 'package:kartka/source_health/scoring/profile.dart';
import 'package:kartka/source_health/scoring/profile_store.dart';

typedef _Snapshot = (List<SourceHealthRecord>, SourceHealthMeta?);

/// A base feed under the profile of a store.
///
/// Records the evaluator already judged with the active profile pass through
/// untouched (its meta says so; a pre-profile run has neither meta.profile
/// nor defaultScore and used DEFAULT), so under DEFAULT the published ranking
/// is exactly what is shown. Otherwise they are re-scored, and the meta's
/// verdict totals are recounted. Records and meta share one subscription to
/// the base feed, and a listener that joins it late (the Sources tab after
/// Browse) first gets the latest snapshot or error: the base re-emits only
/// when the data changes, which may be a week away.
class ScoredHealthFeed implements SourceHealthFeed {
  /// Re-scores the base feed with the store's profile.
  new(this._base, this._store);

  final SourceHealthFeed _base;
  final ScoringProfileStore _store;
  late final Stream<_Snapshot> _shared = _join();

  @override
  Stream<List<SourceHealthRecord>> watch() => _shared.map((s) => s.$1);

  @override
  Stream<SourceHealthMeta?> watchMeta() => _shared.map((s) => s.$2);

  Stream<_Snapshot> _join() {
    final subs = <StreamSubscription<Object?>>[];
    List<SourceHealthRecord>? records;
    SourceHealthMeta? meta;
    var live = false;
    var profileKnown = false;
    _Snapshot? latest;
    (Object, StackTrace)? failure;
    late final StreamController<_Snapshot> out;

    void emit() {
      final r = records;
      if (!live || !profileKnown || r == null) return;
      final snapshot = latest = _apply(r, meta, _store.profile.value);
      failure = null;
      out.add(snapshot);
    }

    void stop() {
      live = false;
      profileKnown = false;
      // The restart re-emits from the kept records once the profile is read.
      latest = null;
      failure = null;
      _store.profile.removeListener(emit);
      for (final s in subs) {
        unawaited(s.cancel());
      }
      subs.clear();
    }

    out = StreamController<_Snapshot>.broadcast(
      onListen: () {
        live = true;
        subs
          ..add(
            _base.watch().listen(
              (r) {
                records = r;
                emit();
              },
              onError: (Object e, StackTrace s) {
                latest = null;
                failure = (e, s);
                out.addError(e, s);
              },
            ),
          )
          ..add(
            _base.watchMeta().listen((m) {
              meta = m;
              emit();
            }, onError: (Object _) {}),
          );
        // Wait for the stored profile, so DEFAULT never flashes.
        unawaited(
          _store.ready.then((_) {
            if (!live) return;
            profileKnown = true;
            _store.profile.addListener(emit);
            emit();
          }),
        );
      },
      onCancel: stop,
    );
    return Stream.multi((listener) {
      if (latest case final snapshot?) listener.add(snapshot);
      if (failure case (final e, final s)?) listener.addError(e, s);
      final sub = out.stream.listen(listener.add, onError: listener.addError);
      listener.onCancel = sub.cancel;
    }, isBroadcast: true);
  }

  _Snapshot _apply(
    List<SourceHealthRecord> records,
    SourceHealthMeta? meta,
    ScoringProfile profile,
  ) {
    final judged = meta?.profile;
    // A run without meta.profile is a pre-profile run (DEFAULT) only when no
    // record carries defaultScore; otherwise the meta is just not read yet.
    final published =
        judged == profile ||
        (judged == null &&
            profile.isDefault &&
            records.every((r) => r.defaultScore == null));
    if (published) return (records, meta);
    final rescored = rescore(records, profile);
    return (rescored, meta?.withVerdicts(countVerdicts(rescored)));
  }
}
