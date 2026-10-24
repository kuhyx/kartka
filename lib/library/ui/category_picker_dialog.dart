import 'package:flutter/material.dart';
import 'package:kartka/core/models/category.dart';

/// Asks which categories the selection belongs to.
///
/// [initial] maps category id to `true` (all selected entries are in it),
/// `false` (none) or `null` (some). Returns only the ids the user changed,
/// or `null` when cancelled.
Future<Map<String, bool>?> pickCategories(
  BuildContext context,
  List<Category> categories,
  Map<String, bool?> initial,
) => showDialog<Map<String, bool>>(
  context: context,
  builder: (_) => _Picker(categories, initial),
);

class _Picker extends StatefulWidget {
  const new(this.categories, this.initial);

  final List<Category> categories;
  final Map<String, bool?> initial;

  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  late final Map<String, bool?> _value = {...widget.initial};

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Set categories'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in widget.categories)
            CheckboxListTile(
              title: Text(c.name),
              tristate: true,
              value: _value[c.id],
              // Mixed or off -> on, on -> off; never back to mixed.
              onChanged: (_) =>
                  setState(() => _value[c.id] = _value[c.id] != true),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, {
          for (final MapEntry(:key, :value) in _value.entries)
            if (value != null && value != widget.initial[key]) key: value,
        }),
        child: const Text('Apply'),
      ),
    ],
  );
}
