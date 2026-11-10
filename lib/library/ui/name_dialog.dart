import 'package:flutter/material.dart';

/// Asks for a name; Enter saves, Escape or Cancel returns `null`.
///
/// The dialog is headed by [icon]; [semanticLabel] is its old worded title,
/// spoken only.
Future<String?> askName(
  BuildContext context, {
  required IconData icon,
  required String semanticLabel,
  String initial = '',
}) => showDialog<String>(
  context: context,
  builder: (_) => _NameDialog(icon, semanticLabel, initial),
);

class _NameDialog extends StatefulWidget {
  const new(this.icon, this.semanticLabel, this.initial);

  final IconData icon;
  final String semanticLabel;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() => Navigator.pop(context, _text.text);

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Icon(widget.icon, size: 48, semanticLabel: widget.semanticLabel),
    content: TextField(
      controller: _text,
      autofocus: true,
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.label_outline, semanticLabel: 'Name'),
      ),
      onSubmitted: (_) => _save(),
    ),
    actions: [
      IconButton(
        style: IconButton.styleFrom(minimumSize: const Size.square(48)),
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.close, semanticLabel: 'Cancel'),
      ),
      IconButton.filled(
        style: IconButton.styleFrom(minimumSize: const Size.square(48)),
        onPressed: _save,
        icon: const Icon(Icons.check, semanticLabel: 'Save'),
      ),
    ],
  );
}
