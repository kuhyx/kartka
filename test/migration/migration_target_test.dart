import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/migration/migration_target.dart';

import 'fakes.dart';

void main() {
  test('titles match exactly up to case and spacing', () {
    expect(isExactTitle(' One  Piece', 'one piece'), isTrue);
    expect(isExactTitle('One Piece', 'One Piece!'), isFalse);
  });

  test('Atsumaru is known by its Suwayomi id or by name', () {
    expect(isAtsumaru(ScriptedSource(atsumaruSourceId, name: 'x').ref), isTrue);
    expect(
      isAtsumaru(ScriptedSource('plugin:atsu', name: 'atsumaru').ref),
      isTrue,
    );
    expect(isAtsumaru(ScriptedSource('mangadex').ref), isFalse);
  });
}
