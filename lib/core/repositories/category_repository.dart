import 'package:kartka/core/models/models.dart';

/// Library categories and which manga belong to them (DOCS-contracts §8).
abstract interface class CategoryRepository {
  /// Current categories, re-emitted on every change.
  Stream<List<Category>> watch();

  /// Inserts or updates [c]; last-writer-wins on `updatedAt`.
  Future<void> upsert(Category c);

  /// Puts [key] in (or takes it out of) category [categoryId].
  // The positional bool is the contract's signature (§8), shared by every
  // part; renaming it to a named parameter is a coordinator decision.
  // ignore: avoid_positional_boolean_parameters
  Future<void> setMembership(MangaKey key, String categoryId, bool member);

  /// Manga key to the ids of the categories it is in (true values only).
  Stream<Map<MangaKey, Set<String>>> watchMembership();
}
