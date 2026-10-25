import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:kartka/core/diagnostics/diagnostic_entry.dart';
import 'package:kartka/core/diagnostics/diagnostics_log.dart';
import 'package:kartka/source_health/install/install_ports.dart';
import 'package:kartka/source_health/model/source_health_record.dart';

/// Navigates to the browse screen of [sourceId].
typedef OpenSourceRoute = void Function(BuildContext context, String sourceId);

/// What one source's action button shows.
enum SourceAction {
  /// The app lists the source (or it cannot be installed): browse it.
  open,

  /// An installer can add the source.
  install,

  /// An install is in flight.
  installing,
}

/// Every http(s) URL, whole: a failure message keeps none of it.
final _url = RegExp(r'''https?://[^\s"'<>]*''', caseSensitive: false);

/// [text] with every http(s) URL replaced by `<url>`.
String stripUrls(String text) => text.replaceAll(_url, '<url>');

/// Install / Open state of every source on the Sources tab and its detail
/// pages, fed by the app's live list of source ids.
///
/// A record installs through Suwayomi when it has `pkg`, else through the
/// plugin repo when it has `plugin`; anything else (native, local, legacy
/// plugins) only opens. Installers are read lazily from the registry.
class SourceInstalls extends ChangeNotifier {
  /// Creates the controller and starts watching [sourceIds].
  new({
    required Stream<Set<String>> sourceIds,
    required this.open,
    SuwayomiExtensionInstaller? Function()? suwayomi,
    PluginRepoInstaller? Function()? plugins,
    this.diagnostics,
    this.now = DateTime.now,
  }) : _suwayomi = suwayomi ?? _none,
       _plugins = plugins ?? _none {
    _sub = sourceIds.listen((ids) {
      _listed = ids;
      notifyListeners();
    });
  }

  static T? _none<T>() => null;

  /// Opens a source's browse screen.
  final OpenSourceRoute open;

  /// Where failed installs are logged.
  final DiagnosticsLog? diagnostics;

  /// Current time, for the log.
  final DateTime Function() now;

  final SuwayomiExtensionInstaller? Function() _suwayomi;
  final PluginRepoInstaller? Function() _plugins;
  late final StreamSubscription<Set<String>> _sub;
  Set<String> _listed = const {};
  final _installed = <String>{};
  final _installing = <String>{};

  bool _canInstall(SourceHealthRecord r) =>
      (r.pkg != null && _suwayomi() != null) ||
      (r.plugin != null && _plugins() != null);

  /// What [r]'s button shows now.
  SourceAction actionOf(SourceHealthRecord r) {
    if (_installing.contains(r.id)) return SourceAction.installing;
    final have = _listed.contains(r.id) || _installed.contains(r.id);
    return have || !_canInstall(r) ? SourceAction.open : SourceAction.install;
  }

  /// Installs [r]; null on success, else the failure message without URLs
  /// (also logged as `sources.install`). Ignored while one is in flight.
  Future<String?> install(SourceHealthRecord r) async {
    if (!_installing.add(r.id)) return null;
    notifyListeners();
    try {
      if (r.pkg case final pkg?) {
        await _suwayomi()!.installExtension(pkg);
      } else {
        final ref = r.plugin!;
        await _plugins()!.installPlugin(repo: ref.repo, id: ref.id);
      }
      _installed.add(r.id);
      return null;
    } on Object catch (e) {
      final message = stripUrls('$e');
      unawaited(
        diagnostics?.append(
          DiagnosticEntry.failure(
            at: now(),
            kind: 'sources.install',
            error: message,
            sourceId: r.id,
          ),
        ),
      );
      return message;
    } finally {
      _installing.remove(r.id);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }
}
