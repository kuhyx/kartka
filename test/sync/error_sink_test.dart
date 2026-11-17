import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/sync/error_sink.dart';
import 'package:kartka/sync/rtdb_transport.dart';

void main() {
  test(
    'writes the shared upload under /kartka/errors; null signed out',
    () async {
      expect(errorSink(null), isNull);
      final db = InMemoryRtdb();
      await errorSink(db)!('kartka/errors', {
        'dev/abc': {'kind': 'x'},
      });
      expect(db.tree['errors'], {
        'dev': {
          'abc': {'kind': 'x'},
        },
      });
    },
  );
}
