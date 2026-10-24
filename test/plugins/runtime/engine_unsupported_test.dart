import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/plugins/runtime/engine_unsupported.dart' as unsupported;

void main() {
  test('the fallback engine refuses to run plugins', () {
    expect(unsupported.createPlatformEngine, throwsUnsupportedError);
  });
}
