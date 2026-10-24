import 'dart:typed_data';

import 'package:kartka/platform/platform.dart';

export 'package:kartka/platform/memory/memory_platform.dart';

/// A picked file holding [bytes].
PickedFile picked(String name, List<int> bytes, {String? relativePath}) =>
    PickedFile(
      name: name,
      relativePath: relativePath,
      read: () async => Uint8List.fromList(bytes),
    );
