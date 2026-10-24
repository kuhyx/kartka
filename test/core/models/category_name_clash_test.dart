// Guards the Category doc in lib/core/models/category.dart: UI files import
// material.dart and the models barrel together, and that must compile.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';

void main() {
  test('Category from the models barrel is usable beside material.dart', () {
    final c = Category(
      id: 'c',
      name: 'Reading',
      order: 0,
      updatedAt: DateTime.utc(2026),
    );
    expect(const Text('x'), isA<Widget>());
    expect(c.name, 'Reading');
  });
}
