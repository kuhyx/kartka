import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// A valid 1x1 transparent PNG, for tests that need a decodable image.
final Uint8List tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

/// Builds a ZIP in memory. Each entry's bytes are its own name unless given,
/// so tests can check page order by decoding the bytes back.
Uint8List buildZip(Map<String, List<int>?> entries) {
  final archive = Archive();
  for (final MapEntry(:key, :value) in entries.entries) {
    if (key.endsWith('/')) {
      archive.add(ArchiveFile.directory(key));
    } else {
      archive.add(ArchiveFile.bytes(key, value ?? utf8.encode(key)));
    }
  }
  return ZipEncoder().encodeBytes(archive);
}

/// A minimal ComicInfo.xml document.
List<int> comicInfoXml({String? series, String? number, String? title}) {
  final b = StringBuffer('<?xml version="1.0"?><ComicInfo>');
  if (series != null) b.write('<Series>$series</Series>');
  if (number != null) b.write('<Number>$number</Number>');
  if (title != null) b.write('<Title>$title</Title>');
  b.write('</ComicInfo>');
  return utf8.encode(b.toString());
}
