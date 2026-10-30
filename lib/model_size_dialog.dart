import 'package:flutter/material.dart';

class ModelSizeDialog extends StatefulWidget {
  const ModelSizeDialog({super.key, required this.scale, required this.width, required this.editWidth});
  final double scale, width;
  final bool editWidth;
  @override State<ModelSizeDialog> createState() => _ModelSizeDialogState();
}
class _ModelSizeDialogState extends State<ModelSizeDialog> {
  final form = GlobalKey<FormState>();
  late final controller = TextEditingController(text:
    (widget.editWidth ? widget.width*widget.scale : widget.scale*100).toStringAsFixed(2));
  double? scaleFor(String? text) {
    final value = double.tryParse((text ?? '').trim().replaceAll(',','.'));
    if (value == null) return null;
    return widget.editWidth ? value/widget.width : value/100;
  }
  @override void dispose() { controller.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AlertDialog(
    title: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.editWidth ? 'Breite ändern' : 'Größe ändern'),
      Wrap(spacing: 8, children: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(onPressed: () {
          if (form.currentState!.validate()) Navigator.pop(context,scaleFor(controller.text));
        }, child: const Text('Übernehmen')),
      ]),
    ]),
    content: Form(key: form, child: TextFormField(controller: controller, autofocus: true,
      decoration: InputDecoration(labelText: widget.editWidth ? 'Breite X in mm' : 'Größe in %'),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: (text) {
        final scale = scaleFor(text);
        return scale == null || !scale.isFinite || scale < .001 || scale > 1000
          ? 'Erlaubt: 0,1 bis 100.000 % der Originalgröße.' : null;
      })),
  );
}
