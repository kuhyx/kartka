import 'package:kartka/core/models/json_fields.dart';

/// A user-defined library category (DOCS-contracts §8; synced per §4).
///
/// Name clash: `package:flutter/foundation.dart` also exports a `Category`
/// (a doc annotation). UI files that import Flutter and the models barrel
/// write `import 'package:flutter/foundation.dart' hide Category;` or import
/// this file with a prefix. `material.dart` alone does not export it.
class Category {
  /// Creates a category.
  const new({
    required this.id,
    required this.name,
    required this.order,
    required this.updatedAt,
    this.removed = false,
  });

  /// Decodes the shape written by [toJson].
  factory fromJson(Map<String, Object?> json) => Category(
    id: readString(json, 'id'),
    name: readString(json, 'name'),
    order: readInt(json, 'order'),
    updatedAt: readDate(json, 'updatedAt'),
    removed: readBool(json, 'removed'),
  );

  /// Stable id (a uuid, or the SY backup's category name on import).
  final String id;

  /// Display name.
  final String name;

  /// Sort position, ascending.
  final int order;

  /// Last-writer-wins clock.
  final DateTime updatedAt;

  /// Tombstone: the category was deleted.
  final bool removed;

  /// JSON shape; [updatedAt] as UTC ISO-8601.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'order': order,
    'updatedAt': writeDate(updatedAt),
    'removed': removed,
  };

  @override
  bool operator ==(Object other) =>
      other is Category &&
      other.id == id &&
      other.name == name &&
      other.order == order &&
      sameInstant(other.updatedAt, updatedAt) &&
      other.removed == removed;

  @override
  int get hashCode =>
      Object.hash(id, name, order, instantHash(updatedAt), removed);

  @override
  String toString() => 'Category($id, $name)';
}
