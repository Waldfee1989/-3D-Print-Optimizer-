import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const lowStockThresholdKey = 'low_stock_threshold_g';
double? stockGrams(Object? value) {
  final n = value is num ? value.toDouble() : double.tryParse('$value'.replaceAll(',','.'));
  return n == null || !n.isFinite || n < 0 ? null : n;
}
class FilamentBalance {
  FilamentBalance(this.brand,this.material,this.color,this.barcode);
  final String brand,material,color,barcode;
  int rolls = 0;
  double grams = 0;
  bool known = true;
}
List<FilamentBalance> filamentBalances(List<Map<String,dynamic>> stock) {
  final groups = <String,FilamentBalance>{};
  for (final roll in stock) {
    final brand = '${roll['brand'] ?? ''}', material = '${roll['material'] ?? ''}',
      color = '${roll['color'] ?? ''}', barcode = '${roll['barcode'] ?? ''}';
    final key = jsonEncode([brand.trim().toLowerCase(),material.trim().toLowerCase(),color.trim().toLowerCase(),barcode.trim()]);
    final group = groups.putIfAbsent(key,() => FilamentBalance(brand,material,color,barcode));
    group.rolls++;
    final grams = stockGrams(roll['grams']);
    if (grams == null) { group.known = false; } else { group.grams += grams; }
  }
  return groups.values.toList()..sort((a,b) => a.grams.compareTo(b.grams));
}
List<FilamentBalance> reorderFilaments(List<Map<String,dynamic>> stock,double threshold) =>
  filamentBalances(stock).where((g) => g.known && g.grams <= threshold).toList();

class LowStockPage extends StatefulWidget {
  const LowStockPage({super.key,required this.stock,required this.threshold,required this.onThresholdChanged});
  final List<Map<String,dynamic>> stock;
  final double threshold;
  final ValueChanged<double> onThresholdChanged;
  @override State<LowStockPage> createState() => _LowStockPageState();
}
class _LowStockPageState extends State<LowStockPage> {
  late double threshold = widget.threshold;
  Future<void> editThreshold() async {
    final value = await showDialog<double>(context: context,builder: (_) => _ThresholdDialog(threshold));
    if (value == null || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setDouble(lowStockThresholdKey,value)) return;
    if (mounted) setState(() => threshold = value);
    widget.onThresholdChanged(value);
  }
  @override Widget build(BuildContext context) {
    final low = reorderFilaments(widget.stock,threshold);
    return Scaffold(appBar: AppBar(title: const Text('Nachbestellen'),actions: [
      IconButton(tooltip: 'Liste kopieren',onPressed: low.isEmpty ? null : () async {
        await Clipboard.setData(ClipboardData(text: low.map((p) => '${p.brand} ${p.material} ${p.color} · noch ${p.grams.toStringAsFixed(0)} g${p.barcode.isEmpty ? '' : ' · ${p.barcode}'}').join('\n')));
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nachbestellliste kopiert.')));
      },icon: const Icon(Icons.copy)),
    ]),body: SafeArea(top: false,child: ListView(padding: const EdgeInsets.all(16),children: [
      Card(child: ListTile(title: Text('Fast leer ab ${threshold.toStringAsFixed(0)} g'),
        subtitle: const Text('Für die Einkaufsliste werden gleiche Filamente zusammengerechnet.'),
        trailing: const Icon(Icons.edit_outlined),onTap: editThreshold)),
      if (low.isEmpty) const Padding(padding: EdgeInsets.all(24),child: Text('Aktuell muss kein erfasstes Filament nachbestellt werden.')),
      for (final p in low) Card(child: ListTile(leading: Icon(p.grams == 0 ? Icons.remove_circle_outline : Icons.warning_amber_rounded,color: const Color(0xffffc780)),
        title: Text('${p.brand} ${p.material} ${p.color}'),subtitle: Text('${p.grams.toStringAsFixed(0)} g auf ${p.rolls} Rolle(n)${p.barcode.isEmpty ? '' : '\nCode: ${p.barcode}'}'))),
      if (filamentBalances(widget.stock).any((p) => !p.known)) const Text('Bei einigen Rollen ist die Restmenge unbekannt. Diese Mengen zuerst im Filamentlager prüfen.'),
      const Text('Restmengen nach dem Drucken im Filamentlager aktualisieren.'),
    ])));
  }
}
class _ThresholdDialog extends StatefulWidget {
  const _ThresholdDialog(this.value);
  final double value;
  @override State<_ThresholdDialog> createState() => _ThresholdDialogState();
}
class _ThresholdDialogState extends State<_ThresholdDialog> {
  final form = GlobalKey<FormState>();
  late final controller = TextEditingController(text: widget.value.toStringAsFixed(0));
  @override void dispose() { controller.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AlertDialog(title: Column(mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,children: [const Text('Fast-leer-Grenze'),
      FilledButton(onPressed: () {
        if (form.currentState!.validate()) Navigator.pop(context,double.parse(controller.text.replaceAll(',','.')));
      },child: const Text('Speichern'))]),content: Form(key: form,child: TextFormField(controller: controller,
        decoration: const InputDecoration(labelText: 'Restmenge in g'),keyboardType: const TextInputType.numberWithOptions(decimal: true),
        validator: (text) { final n = stockGrams(text); return n == null || n > 100000 ? 'Bitte eine Menge von 0 bis 100.000 g eingeben.' : null; })));
}
