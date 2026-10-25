/// Display words for §5 enums, shared by the UI and the search index (which
/// must find a record by the words the screen shows).
library;

import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/source_health/model/source_health_record.dart';

/// Display name of a §5 origin.
String originLabel(String origin) => switch (origin) {
  'native' => 'Native',
  'suwayomi' => 'Suwayomi',
  'plugin' => 'JS plugin',
  'local' => 'Local',
  _ => origin,
};

/// The word shown for a verdict.
String verdictLabel(HealthVerdict v) => switch (v) {
  HealthVerdict.keep => 'Keep',
  HealthVerdict.cut => 'Cut',
  HealthVerdict.pending => 'Pending',
};

/// The evaluator's `langScope` in words: which languages it tested.
String langScopeLabel(String scope) => switch (scope) {
  'en+ja' => 'tested EN + JA only',
  'unrestricted' => 'tested all languages',
  _ => 'tested $scope',
};

/// `Suwayomi · en · tested EN + JA only` (plus the id when [withId]),
/// skipping parts the record does not have.
String sourceLine(SourceHealthRecord r, {bool withId = false}) => [
  originLabel(r.origin),
  r.lang,
  if (r.langScope case final scope?) langScopeLabel(scope),
  if (withId) r.id,
].where((s) => s.isNotEmpty).join(' · ');
