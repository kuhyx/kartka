import 'package:kartka/app/feature.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/sources/local/import_local_tile.dart';
import 'package:kartka/sources/local/local_library.dart';
import 'package:kartka/sources/local/local_source.dart';

/// The local CBZ/folder part: the `local` source (as a [SourceProvider]),
/// its [LocalLibrary] (for parts that want `changes`), and the
/// "Import local files" tile on the More tab.
KartkaFeature localFeature(KartkaEnv env) {
  final library = LocalLibrary(blobs: env.platform.blobs, kv: env.platform.kv);
  return KartkaFeature(
    id: 'source-local',
    settingsTiles: [
      (_) => ImportLocalTile(library: library, picker: env.platform.filePicker),
    ],
    services: [
      StaticSourceProvider([LocalSource(library)]),
      library,
    ],
  );
}
