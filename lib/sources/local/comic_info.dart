import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable;
import 'package:xml/xml.dart';

/// The subset of an archive's `ComicInfo.xml` (ComicRack schema) that Kartka
/// uses to name and group chapters.
@immutable
class ComicInfo {
  /// Creates metadata; every field is optional, like in the schema.
  const new({this.title, this.series, this.number});

  /// Chapter title (`<Title>`), `null` when absent or blank.
  final String? title;

  /// Series name (`<Series>`), trimmed, `null` when absent or blank.
  final String? series;

  /// Chapter number (`<Number>`). The schema stores a string; non-numeric
  /// values such as `Extra` become `null`.
  final double? number;

  /// Parses [xml]; returns `null` for malformed XML or a non-ComicInfo root.
  static ComicInfo? parse(String xml) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(_stripBom(xml));
    } on XmlException {
      return null;
    }
    final root = doc.rootElement;
    if (root.name.local != 'ComicInfo') return null;
    final number = _text(root, 'Number');
    return ComicInfo(
      title: _text(root, 'Title'),
      series: _text(root, 'Series'),
      number: number == null ? null : _parseNumber(number),
    );
  }

  /// Parses raw file [bytes], tolerating invalid UTF-8 and a BOM.
  static ComicInfo? parseBytes(List<int> bytes) =>
      parse(utf8.decode(bytes, allowMalformed: true));

  @override
  bool operator ==(Object other) =>
      other is ComicInfo &&
      other.title == title &&
      other.series == series &&
      other.number == number;

  @override
  int get hashCode => Object.hash(title, series, number);

  @override
  String toString() => 'ComicInfo($series #$number: $title)';
}

/// Whether an archive entry [path] is a `ComicInfo.xml` (any case, any depth).
bool isComicInfoPath(String path) =>
    path.split('/').last.toLowerCase() == 'comicinfo.xml';

String _stripBom(String s) => s.startsWith('﻿') ? s.substring(1) : s;

String? _text(XmlElement root, String tag) {
  for (final e in root.childElements) {
    if (e.name.local == tag) {
      final value = e.innerText.trim();
      return value.isEmpty ? null : value;
    }
  }
  return null;
}

double? _parseNumber(String raw) => double.tryParse(raw.replaceAll(',', '.'));
