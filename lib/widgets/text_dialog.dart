import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// Asks for a text, starting from [initial], until [validator] takes it. Null
/// if cancelled.
Future<String?> askText(
  BuildContext context, {
  required String title,
  String initial = '',
  String? helper,
  String? Function(String text)? validator,
  bool number = false,
  bool multiline = false,
}) => showDialog<String>(
  context: context,
  builder: (_) => _TextDialog(
    title: title,
    initial: initial,
    helper: helper,
    validator: validator,
    number: number,
    multiline: multiline,
  ),
);

final class _TextDialog extends HookWidget {
  final String title;
  final String initial;
  final String? helper;
  final String? Function(String text)? validator;
  final bool number;
  final bool multiline;

  const _TextDialog({
    required this.title,
    required this.initial,
    required this.helper,
    required this.validator,
    required this.number,
    required this.multiline,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = useTextEditingController(text: initial);
    final formKey = useMemoized(GlobalKey<FormState>.new);

    void save() {
      if (formKey.currentState!.validate()) {
        Navigator.pop(context, controller.text);
      }
    }

    return AlertDialog(
      title: Text(title),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: controller,
          autofocus: true,
          keyboardType: number
              ? TextInputType.number
              : multiline
              ? TextInputType.multiline
              : null,
          inputFormatters: [if (number) FilteringTextInputFormatter.digitsOnly],
          minLines: 1,
          maxLines: multiline ? 5 : 1,
          decoration: InputDecoration(helperText: helper, helperMaxLines: 3),
          validator: validator == null ? null : (text) => validator!(text!),
          onFieldSubmitted: multiline ? null : (_) => save(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        TextButton(onPressed: save, child: Text(l10n.save)),
      ],
    );
  }
}
