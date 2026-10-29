import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/redact.dart';

void main() {
  group('redactUrlQueries', () {
    test('is idempotent, so a re-read entry is not redacted twice', () {
      const once = 'GET https://<redacted>@h.test/a.json?<redacted> failed';
      expect(redactUrlQueries(once), once);
      expect(
        redactUrlQueries('x https://h.test/#<redacted>'),
        'x https://h.test/#<redacted>',
      );
    });

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
    test('URL userinfo is redacted, scheme, host and path stay', () {
      expect(
        redactUrlQueries('GET https://user:pa55@h.test/p failed'),
        'GET https://<redacted>@h.test/p failed',
      );
      expect(redactUrlQueries('HTTP://tok@h.test'), 'HTTP://<redacted>@h.test');
    });

    test('userinfo and a query in one URL are both redacted', () {
      expect(
        redactUrlQueries('uri=https://u:p@h.test/p?auth=T#f'),
        'uri=https://<redacted>@h.test/p?<redacted>',
      );
    });

    test('an @ outside the authority is not userinfo', () {
      const plain = ['https://h.test/p/@me', 'mail a@b.c', 'https://h.test'];
      for (final s in plain) {
        expect(redactUrlQueries(s), s);
      }
    });
  });
}
