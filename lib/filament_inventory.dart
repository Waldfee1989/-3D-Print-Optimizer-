import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

String filamentCode(String value) => value.trim();

class FilamentCatalog {
  FilamentCatalog(this.preferences);
  final SharedPreferences preferences;
  static const storageKey = 'filament_barcode_catalog_v1';

  Map<String, dynamic>? lookup(String code, List<Map<String, dynamic>> stock) {
    final key = filamentCode(code);
    if (key.isEmpty) return null;
    try {
      final saved = jsonDecode(preferences.getString(storageKey) ?? '{}') as Map;
      if (saved[key] is Map) return _profile(Map<String, dynamic>.from(saved[key] as Map));
    } catch (_) { /* Existing rolls remain available if the separate catalog is damaged. */ }
    for (final roll in stock) {
      if (filamentCode('${roll['barcode'] ?? ''}') == key) return _profile(roll);
    }
    return null;
  }

  Map<String, dynamic> _profile(Map<String, dynamic> item) => {
    for (final key in ['brand', 'material', 'color']) key: '${item[key] ?? ''}',
  };

  Future<void> remember(Map<String, dynamic> roll) async {
    final code = filamentCode('${roll['barcode'] ?? ''}');
    if (code.isEmpty) return;
    Map<String, dynamic> saved;
    try { saved = Map<String, dynamic>.from(jsonDecode(preferences.getString(storageKey) ?? '{}') as Map); }
    catch (_) { saved = {}; }
    saved[code] = _profile(roll);
    if (!await preferences.setString(storageKey, jsonEncode(saved))) {
      throw const FormatException('Barcode-Zuordnung konnte nicht gespeichert werden.');
    }
  }
}

class FilamentEditor extends StatefulWidget {
  const FilamentEditor({super.key, this.barcode = '', this.profile, this.existing});
  final String barcode;
  final Map<String, dynamic>? profile, existing;
  @override State<FilamentEditor> createState() => _FilamentEditorState();
}

class FilamentCodeDialog extends StatefulWidget {
  const FilamentCodeDialog({super.key});
  @override State<FilamentCodeDialog> createState() => _FilamentCodeDialogState();
}

class _FilamentCodeDialogState extends State<FilamentCodeDialog> {
  final code = TextEditingController();
  @override void dispose() { code.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AlertDialog(
    title: const Text('Filamentcode eingeben'),
    content: TextField(controller: code, autofocus: true, maxLength: 512,
      decoration: const InputDecoration(labelText: 'Code auf der Rolle'),
      onSubmitted: (value) => Navigator.pop(context, value.trim())),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
      FilledButton(onPressed: () => Navigator.pop(context, code.text.trim()), child: const Text('Suchen')),
    ],
  );
}

class _FilamentEditorState extends State<FilamentEditor> {
  final form = GlobalKey<FormState>();
  late final code = TextEditingController(text: '${widget.existing?['barcode'] ?? widget.barcode}');
  late final brand = TextEditingController(text: '${widget.existing?['brand'] ?? widget.profile?['brand'] ?? 'SUNLU'}');
  late final material = TextEditingController(text: '${widget.existing?['material'] ?? widget.profile?['material'] ?? 'PLA'}');
  late final color = TextEditingController(text: '${widget.existing?['color'] ?? widget.profile?['color'] ?? ''}');
  // A product barcode identifies a product, not an individual roll's balance.
  late final grams = TextEditingController(text: '${widget.existing?['grams'] ?? 1000}');

  @override void dispose() {
    for (final controller in [code, brand, material, color, grams]) { controller.dispose(); }
    super.dispose();
  }

  @override Widget build(BuildContext context) => AlertDialog(
    title: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(widget.existing == null ? 'Filament hinzufügen' : 'Filament bearbeiten'),
      Wrap(spacing: 8, children: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
      FilledButton(onPressed: () {
        if (!form.currentState!.validate()) return;
        Navigator.pop(context, <String, dynamic>{
          ...?widget.existing,
          'barcode': filamentCode(code.text), 'brand': brand.text.trim(),
          'material': material.text.trim(), 'color': color.text.trim(),
          'grams': double.parse(grams.text.trim().replaceAll(',', '.')),
        });
      }, child: Text(widget.existing == null ? 'Hinzufügen' : 'Speichern')),
      ]),
    ]),
    content: SingleChildScrollView(child: Form(key: form, child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        if (widget.existing == null && widget.barcode.isNotEmpty)
          Text(widget.profile == null ? 'Barcode noch unbekannt. Angaben einmal prüfen und speichern.'
            : 'Gespeicherte Zuordnung geladen. Restmenge für diese neue Rolle prüfen.'),
        TextFormField(controller: code, decoration: const InputDecoration(labelText: 'Barcode'),
          maxLength: 512),
        for (final field in [(brand, 'Hersteller'), (material, 'Material'), (color, 'Farbe')])
          TextFormField(controller: field.$1, decoration: InputDecoration(labelText: field.$2),
            validator: (value) => (value ?? '').trim().isEmpty ? 'Bitte ${field.$2} eintragen.' : null),
        TextFormField(controller: grams, decoration: const InputDecoration(labelText: 'Restmenge (g)'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (value) {
            final amount = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
            return amount == null || !amount.isFinite || amount < 0
                ? 'Bitte eine gültige Restmenge ab 0 g eintragen.' : null;
          }),
      ]))),

  );
}

// One camera frame may contain multiple codes and consecutive frames repeat them.
class FilamentScanLatch {
  bool completed = false;
  String? accept(Iterable<String?> values) {
    if (completed) return null;
    final codes = values.whereType<String>().map(filamentCode)
        .where((code) => code.isNotEmpty && code.length <= 512).toSet();
    if (codes.length != 1) return null;
    completed = true;
    return codes.single;
  }
}
