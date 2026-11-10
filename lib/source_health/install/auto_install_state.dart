import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:kartka/platform/key_value_store.dart';
import 'package:kartka/source_health/model/json_read.dart';

/// Where an auto-installed source failed.
enum AutoInstallStage {
  /// The install itself failed: the source is not installed.
  install,

  /// Installed, but its first popular page did not load.
  test,
}

/// Why one source failed its auto-install, redacted (no URLs).
@immutable
class AutoInstallFailure {
  /// Creates a failure at [stage].
  const new(this.stage, this.reason);

  /// Parses [toJson]'s shape; null when [json] is not one. An unknown stage
  /// reads as [AutoInstallStage.install] (the source needs attention).
  static AutoInstallFailure? fromJson(Object? json) {
    final m = asMap(json);
    final reason = m == null ? null : readString(m, 'reason');
    if (reason == null) return null;
    final test = readString(m!, 'stage') == AutoInstallStage.test.name;
    return AutoInstallFailure(
      test ? AutoInstallStage.test : AutoInstallStage.install,
      reason,
    );
  }

  /// The failed step.
  final AutoInstallStage stage;

  /// The redacted reason.
  final String reason;

  /// The line the Sources card shows under the source's action.
  String get flag => switch (stage) {
    AutoInstallStage.install => 'Auto-install failed: $reason',
    AutoInstallStage.test => 'Installed — test failed: $reason',
  };

  /// The stored JSON.
  Map<String, Object?> toJson() => {'stage': stage.name, 'reason': reason};

  @override
  bool operator ==(Object other) =>
      other is AutoInstallFailure &&
      other.stage == stage &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(stage, reason);
}

/// What the last Keep auto-install did, stored per device: plugins install
/// per device, so a synced marker would hide a run from the other device.
@immutable
class AutoInstallState {
  /// Creates a state; all empty means "never ran".
  const new({
    this.publishId,
    this.installed = const [],
    this.failures = const {},
    this.librarySources = const [],
  });

  /// Parses [toJson]'s shape; anything unreadable reads as empty.
  factory fromJson(Object? json) {
    final m = asMap(json) ?? const {};
    final failures = asMap(m['failures']) ?? const {};
    return AutoInstallState(
      publishId: readString(m, 'publishId'),
      installed: readStrings(m, 'installed'),
      librarySources: readStrings(m, 'librarySources'),
      failures: {
        for (final MapEntry(:key, :value) in failures.entries)
          key: ?AutoInstallFailure.fromJson(value),
      },
    );
  }

  /// Key in the device-local [KeyValueStore].
  static const String kvKey = 'sourceHealth.autoInstall';

  /// The stored state of [kv]; empty when absent or unreadable.
  static Future<AutoInstallState> load(KeyValueStore kv) async {
    final raw = await kv.get(kvKey);
    if (raw == null) return const AutoInstallState();
    try {
      return AutoInstallState.fromJson(jsonDecode(raw));
    } on FormatException {
      return const AutoInstallState();
    }
  }

  /// Stores this state in [kv].
  Future<void> save(KeyValueStore kv) => kv.set(kvKey, jsonEncode(toJson()));

  /// The publish (run id) fully reconciled; null before the first one.
  final String? publishId;

  /// Source ids the last run installed (failed tests included).
  final List<String> installed;

  /// Sources whose install or test failed, by source id.
  final Map<String, AutoInstallFailure> failures;

  /// The library's source ids [publishId] was reconciled with, sorted
  /// (empty in state stored before library sources were installed).
  final List<String> librarySources;

  /// The numbers behind [status]: sources installed, failed tests and
  /// failed installs.
  ({int installed, int tests, int installs}) get counts {
    final t = failures.values
        .where((f) => f.stage == AutoInstallStage.test)
        .length;
    return (
      installed: installed.length,
      tests: t,
      installs: failures.length - t,
    );
  }

  /// One quiet line about the last run, e.g. "Installed 5 sources, 1
  /// failed its test"; null when it installed and flagged nothing.
  String? get status {
    final (installed: n, tests: t, :installs) = counts;
    // The first count names the noun: "Installed 5 sources, 1 failed its
    // test", or "2 sources failed to install" when none installed.
    var named = false;
    String count(int k) {
      if (named) return '$k';
      named = true;
      return '$k source${k == 1 ? '' : 's'}';
    }

    final parts = [
      if (n > 0) 'Installed ${count(n)}',
      if (t > 0) '${count(t)} failed ${t == 1 ? 'its test' : 'their tests'}',
      if (installs > 0) '${count(installs)} failed to install',
    ];
    return parts.isEmpty ? null : parts.join(', ');
  }

  /// The stored JSON.
  Map<String, Object?> toJson() => {
    'publishId': publishId,
    'installed': installed,
    'failures': {for (final e in failures.entries) e.key: e.value.toJson()},
    'librarySources': librarySources,
  };

  @override
  bool operator ==(Object other) =>
      other is AutoInstallState && _equality.equals(other.toJson(), toJson());

  @override
  int get hashCode => _equality.hash(toJson());
}

const _equality = DeepCollectionEquality();
