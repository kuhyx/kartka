import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/diagnostics/report_redact.dart';

void main() {
  test('URL queries and userinfo go, as in the local log', () {
    expect(
      redactForReport('GET https://u:p@db.test/a.json?auth=SECRET failed'),
      'GET https://<redacted>@db.test/a.json?<redacted> failed',
    );
  });

  test('emails, bearer tokens and JWTs are replaced', () {
    final out = redactForReport(
      'signed in as kuhy.someone@example.com, Authorization: Bearer abc.def '
      'id eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiIxIn0.c2lnbmF0dXJl',
    );
    expect(out, isNot(contains('kuhy.someone')));
    expect(out, contains('<email>'));
    expect(out, isNot(contains('abc.def')));
    expect(out, isNot(contains('eyJ')));
  });

  test('named secrets lose their values', () {
    final out = redactForReport(
      'cookie: sid=XYZ; password=hunter2 token=T0K api_key: K3Y secret=S',
    );
    for (final leak in ['XYZ', 'hunter2', 'T0K', 'K3Y', '=S']) {
      expect(out, isNot(contains(leak)));
    }
    expect(out, contains('password=<redacted>'));
  });

  test('home directories lose the user name', () {
    expect(
      redactForReport('at /home/kuhy/src/x.dart and /Users/k/y'),
      'at ~/src/x.dart and ~/y',
    );
  });

  test('plain error text is unchanged', () {
    const text =
        'SuwayomiException: Exception while fetching data '
        '(/fetchChapterPages) : CEF is disabled';
    expect(redactForReport(text), text);
  });
}
