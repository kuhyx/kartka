import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/plugins/runtime/engine_quickjs.dart';

import 'extension_cases.dart';

/// The Android engine. Needs flutter_js's Linux library: run with
/// `LIBQUICKJSC_TEST_PATH=<flutter_js>/linux/shared/libquickjs_c_bridge_plugin.so`.
void main() {
  if (Platform.environment['LIBQUICKJSC_TEST_PATH'] == null) {
    test('QuickJS extensions', () {}, skip: 'LIBQUICKJSC_TEST_PATH not set');
    return;
  }
  extensionCases(QuickJsEngine.new);
}
