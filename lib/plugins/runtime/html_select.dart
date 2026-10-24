import 'package:html/parser.dart' as html_parser;
import 'package:kartka/plugins/runtime/host_api.dart';

/// `kartka.html.select`: all elements of [html] matching the CSS [selector].
///
/// Throws [ArgumentError] for an unparseable selector.
List<HtmlMatch> selectHtml(String html, String selector) {
  final doc = html_parser.parse(html);
  try {
    return [
      for (final e in doc.querySelectorAll(selector))
        HtmlMatch(
          text: e.text.trim(),
          attrs: {for (final a in e.attributes.entries) '${a.key}': a.value},
          html: e.outerHtml,
        ),
    ];
  } on Object catch (e) {
    throw ArgumentError('bad CSS selector "$selector": $e');
  }
}
