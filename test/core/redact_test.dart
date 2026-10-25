import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/redact.dart';

void main() {
  group('redactUrlQueries', () {
    test('an RTDB auth token never survives', () {
      expect(
        redactUrlQueries(
          'FirebaseSyncError: 401 at '
          'https://x.firebaseio.com/kartka/a.json?auth=SECRET123 failed',
        ),
        'FirebaseSyncError: 401 at '
        'https://x.firebaseio.com/kartka/a.json?<redacted> failed',
      );
    });

    test('the live API key message keeps scheme, host and path', () {
      expect(
        redactUrlQueries(
          'ClientException: Connection failed, '
          'uri=https://securetoken.googleapis.com/v1/token?key=AIzaKEY',
        ),
        'ClientException: Connection failed, '
        'uri=https://securetoken.googleapis.com/v1/token?<redacted>',
      );
    });

    test('every URL is redacted, a comma does not end the query', () {
      expect(
        redactUrlQueries(
          'a HTTP://h.test?a=1,key=K then (https://g.test/p/q?b=2&c=3)',
        ),
        'a HTTP://h.test?<redacted> then (https://g.test/p/q?<redacted>',
      );
    });

    test('a query stops at whitespace and quotes', () {
      expect(
        redactUrlQueries('"https://h.test/p?t=1" and \'http://h.test/?u=2\''),
        '"https://h.test/p?<redacted>" and \'http://h.test/?<redacted>\'',
      );
    });

    test('a fragment is redacted too (implicit-grant tokens live there)', () {
      expect(
        redactUrlQueries('https://h.test/cb#access_token=TOKEN&x=1'),
        'https://h.test/cb#<redacted>',
      );
      expect(
        redactUrlQueries('https://h.test/p?a=1#frag'),
        'https://h.test/p?<redacted>',
      );
    });

    test('text without a URL query is unchanged', () {
      const plain = [
        'Are you sure? Yes.',
        'SocketException: Failed host lookup: h.test?',
        'https://h.test/path/only',
        '',
      ];
      for (final s in plain) {
        expect(redactUrlQueries(s), s);
      }
    });
  });
}
