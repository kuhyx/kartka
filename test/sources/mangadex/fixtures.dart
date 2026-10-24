import 'dart:convert';
import 'dart:io';

/// Raw text of a recorded MangaDex response under test/fixtures/mangadex/.
String fixture(String name) =>
    File('test/fixtures/mangadex/$name').readAsStringSync();

/// A recorded response decoded as a JSON object.
Map<String, Object?> fixtureObject(String name) =>
    jsonDecode(fixture(name)) as Map<String, Object?>;
