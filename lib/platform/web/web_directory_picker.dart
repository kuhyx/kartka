// coverage:ignore-file
// Browser-only DOM glue (an <input webkitdirectory>); exercised by the web
// build, not the VM test runner.
import 'dart:async';
import 'dart:js_interop';

import 'package:kartka/platform/file_picker.dart';
import 'package:web/web.dart' as web;

/// Lets the user pick a folder; every file in it, with relative paths.
Future<List<PickedFile>> pickWebDirectory() {
  final done = Completer<List<PickedFile>>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..multiple = true
    ..setAttribute('webkitdirectory', '');
  input
    ..addEventListener(
      'change',
      ((web.Event _) => done.complete(_files(input.files))).toJS,
    )
    ..addEventListener(
      'cancel',
      ((web.Event _) => done.complete(const [])).toJS,
    )
    ..click();
  return done.future;
}

List<PickedFile> _files(web.FileList? list) => [
  for (var i = 0; i < (list?.length ?? 0); i++)
    if (list!.item(i) case final web.File file)
      PickedFile(
        name: file.name,
        relativePath: file.webkitRelativePath.isEmpty
            ? null
            : file.webkitRelativePath,
        read: () async =>
            (await file.arrayBuffer().toDart).toDart.asUint8List(),
      ),
];
