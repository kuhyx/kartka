import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/sources/mangadex/mangadex_settings.dart';

void main() {
  group('MangadexSettings', () {
    test('defaults are en, no data saver, safe + suggestive', () {
      const s = MangadexSettings.defaults;
      expect(s.languages, ['en']);
      expect(s.dataSaver, isFalse);
      expect(s.ratings, {ContentRating.safe, ContentRating.suggestive});
    });

    test('json round trip keeps every field', () {
      const s = MangadexSettings(
        languages: ['pl', 'en'],
        dataSaver: true,
        ratings: {ContentRating.erotica, ContentRating.safe},
      );
      final back = MangadexSettings.fromJson(s.toJson());
      expect(back, s);
      expect(back.hashCode, s.hashCode);
      expect(s.toJson()['ratings'], ['safe', 'erotica']);
    });

    test('missing or empty fields fall back to defaults', () {
      expect(MangadexSettings.fromJson(const {}), MangadexSettings.defaults);
      expect(
        MangadexSettings.fromJson(const {
          'languages': <String>[],
          'ratings': <String>[],
        }),
        MangadexSettings.defaults,
      );
    });

    test('unknown rating names are dropped', () {
      final s = MangadexSettings.fromJson(const {
        'ratings': ['safe', 'bogus'],
      });
      expect(s.ratings, {ContentRating.safe});
    });

    test('copyWith replaces only the given fields', () {
      const s = MangadexSettings.defaults;
      expect(s.copyWith(dataSaver: true).dataSaver, isTrue);
      expect(s.copyWith(languages: ['ja']).languages, ['ja']);
      expect(s.copyWith(ratings: {ContentRating.pornographic}).ratings, {
        ContentRating.pornographic,
      });
      expect(s.copyWith(), s);
    });

    test('equality distinguishes each field', () {
      const s = MangadexSettings.defaults;
      expect(s == s.copyWith(dataSaver: true), isFalse);
      expect(s == s.copyWith(languages: ['ja']), isFalse);
      expect(s == s.copyWith(ratings: {ContentRating.safe}), isFalse);
      expect(s == Object(), isFalse);
    });

    test('rating labels are human readable', () {
      expect(ContentRating.values.map((r) => r.label), [
        'Safe',
        'Suggestive',
        'Erotica',
        'Pornographic',
      ]);
    });
  });
}
