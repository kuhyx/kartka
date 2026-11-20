import 'package:kartka/core/models/models.dart';

/// Atsumaru's id through Suwayomi (Keiyoushi `en.atsumaru`, contracts §1).
const String atsumaruSourceId = 'suwayomi:2327480808438768017';

/// Atsumaru's display name, matched when it arrives under another id (a
/// plugin or a native port).
const String atsumaruName = 'Atsumaru';

/// Whether [ref] is Atsumaru.
bool isAtsumaru(SourceRef ref) =>
    ref.id == atsumaruSourceId ||
    ref.name.toLowerCase() == atsumaruName.toLowerCase();

String _normal(String title) =>
    title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Whether two titles are the same up to case and whitespace: an exact
/// match.
bool isExactTitle(String a, String b) => _normal(a) == _normal(b);
