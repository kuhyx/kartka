import 'package:kartka/app/feature.dart';
import 'package:kartka/plugins/mangayomi/mangayomi_repo_adapter.dart';

/// Mangayomi JS extensions as Kartka plugins (append `mangayomiFeature,`).
///
/// Supplies one service, the [MangayomiRepoAdapter]: the plugins feature's
/// `PluginManager` asks it about every repo index, so Mangayomi repos are
/// added, browsed and installed on the Plugins screen, and their sources
/// come from that feature's single `SourceProvider`.
KartkaFeature mangayomiFeature(KartkaEnv env) =>
    KartkaFeature(id: 'mangayomi', services: [MangayomiRepoAdapter()]);
