/// Display words for §5 enums, shared by the UI and the search index (which
/// must find a record by the words the screen shows).
library;

import 'package:kartka/browse/source_health_lookup.dart';

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
