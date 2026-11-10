import 'package:flutter/material.dart';
import 'package:kartka/browse/language_filter.dart';

/// A language bucket without words: its code upper-cased (`EN`, `PT-BR`),
/// or a globe for [kAllLanguages]. The language name ([languageLabel]) is
/// spoken only.
class LanguageMark extends StatelessWidget {
  /// Marks [bucket] (a [languageBucket]) in [style].
  const new(this.bucket, {this.style, super.key});

  /// The language bucket.
  final String bucket;

  /// Text style of the code; the globe takes its colour.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => bucket == kAllLanguages
      ? Icon(
          Icons.public,
          color: style?.color,
          semanticLabel: languageLabel(bucket),
        )
      : Text(
          bucket.toUpperCase(),
          style: style,
          semanticsLabel: languageLabel(bucket),
        );
}
