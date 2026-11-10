import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/ui/spoken_label.dart';

/// The [Icon]s spoken as [label] (textgate: the old wording lives on as an
/// icon's `semanticLabel`). Unlike `find.bySemanticsLabel` it does not care
/// whether a parent button merged the label into its own node.
Finder spokenIcon(Pattern label) => find.byWidgetPredicate(
  (w) =>
      w is Icon &&
      switch (label) {
        final String s => w.semanticLabel == s,
        _ => label.allMatches(w.semanticLabel ?? '').isNotEmpty,
      },
);

/// Any widget whose spoken-only label contains [part]: an [Icon]'s
/// `semanticLabel`, a [Text]'s `semanticsLabel` or a [SpokenLabel]'s. For
/// long spoken sentences checked by a fragment.
Finder spokenContaining(String part) => find.byWidgetPredicate(
  (w) => switch (w) {
    Icon(:final semanticLabel?) => semanticLabel.contains(part),
    Text(:final semanticsLabel?) => semanticsLabel.contains(part),
    SpokenLabel(:final semanticLabel) => semanticLabel.contains(part),
    _ => false,
  },
);
