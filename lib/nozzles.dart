import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const nozzleStorageKey = 'nozzle_inventory_v1';
class OwnedNozzle {
  const OwnedNozzle({required this.id,required this.printer,required this.diameter,required this.material,required this.quantity});
  final String id,printer,material;
  final double diameter;
  final int quantity;
  Map<String,dynamic> toJson() => {'id': id,'printer': printer,'diameter': diameter,'material': material,'quantity': quantity};
  factory OwnedNozzle.fromJson(Map<String,dynamic> m) => OwnedNozzle(id: m['id'] as String,printer: m['printer'] as String,
    diameter: (m['diameter'] as num).toDouble(),material: m['material'] as String,quantity: m['quantity'] as int);
}
Future<List<OwnedNozzle>> loadNozzles({String? seedPrinter,String? seedDiameter}) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(nozzleStorageKey);
  if (raw != null) return (jsonDecode(raw) as List).map((e) => OwnedNozzle.fromJson(Map<String,dynamic>.from(e as Map))).toList();
  final diameter = double.tryParse((seedDiameter ?? '').replaceAll(',','.'));
  if (seedPrinter != null && diameter != null && diameter.isFinite && diameter >= .1 && diameter <= 2) {
    final rows = [OwnedNozzle(id: 'setup',printer: seedPrinter,diameter: diameter,material: 'Unbekannt',quantity: 1)];
    await saveNozzles(rows); return rows;
  }
  return [];
}
Future<void> saveNozzles(List<OwnedNozzle> rows) async {
  final prefs = await SharedPreferences.getInstance();
  if (!await prefs.setString(nozzleStorageKey,jsonEncode(rows.map((n) => n.toJson()).toList()))) throw StateError('Düsen konnten nicht gespeichert werden.');
}
OwnedNozzle? recommendOwnedNozzle(List<OwnedNozzle> all,String printer,{required bool fine,required bool fast,required bool functional}) {
  final rows = all.where((n) => n.printer.trim().toLowerCase() == printer.trim().toLowerCase() && n.quantity > 0 && n.diameter >= .1 && n.diameter <= 2).toList();
  if (rows.isEmpty) return null;
  final target = fine ? .2 : fast || functional ? .6 : .4;
  rows.sort((a,b) => (a.diameter-target).abs().compareTo((b.diameter-target).abs()));
  return rows.first;
}
({double layer,double first,double line,int top,int bottom}) nozzleGeometry(double diameter,String mode) {
  final ratio = mode == 'Maximale Qualität' ? .3 : mode == 'Ausgewogen' ? .4 : .5;
  final layer = double.parse(math.max(.05,diameter*ratio).toStringAsFixed(3));
  return (layer: layer,first: math.min(.25,diameter*.5),line: double.parse((diameter*1.05).toStringAsFixed(3)),
    top: ((mode == 'Schneller Druck' ? 1.0 : .8)/layer).ceil(),bottom: ((mode == 'Schneller Druck' ? .8 : .6)/layer).ceil());
}
class NozzleInventoryPage extends StatefulWidget {
  const NozzleInventoryPage({super.key,required this.printer,required this.installed});
  final String printer,installed;
  @override State<NozzleInventoryPage> createState() => _NozzleInventoryPageState();
}
class _NozzleInventoryPageState extends State<NozzleInventoryPage> {
  List<OwnedNozzle>? rows;
  String? error;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    try { final data = await loadNozzles(seedPrinter: widget.printer,seedDiameter: widget.installed); if (mounted) setState(() => rows = data); }
    catch (_) { if (mounted) setState(() => error = 'Düsen konnten nicht geladen werden.'); }
  }
  Future<void> edit([int? index]) async {
    final nozzle = await showDialog<OwnedNozzle>(context: context,builder: (_) => _NozzleEditor(printer: widget.printer,existing: index == null ? null : rows![index]));
    if (nozzle == null || !mounted) return;
    final next = [...rows!]; if (index == null) { next.add(nozzle); } else { next[index] = nozzle; }
    try { await saveNozzles(next); if (mounted) setState(() => rows = next); }
    catch (_) { if (mounted) setState(() => error = 'Düse konnte nicht gespeichert werden.'); }
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Meine Düsen'),actions: [
    IconButton(tooltip: 'Düse hinzufügen',onPressed: rows == null ? null : () => edit(),icon: const Icon(Icons.add)),
  ]),body: SafeArea(top: false,child: rows == null ? Center(child: error == null ? const CircularProgressIndicator() : Text(error!)) : ListView(
    padding: const EdgeInsets.all(16),children: [
      Text('${widget.printer} · eingebaut: ${widget.installed} mm'),
      const Text('Nur Düsen eintragen, die zu deinem Drucker passen. Die eingebaute Düse wird aus der Einrichtung übernommen.'),
      if (error != null) Text(error!),
      if (rows!.isEmpty) const Text('Noch keine Düsen eingetragen.'),
      for (var i = 0; i < rows!.length; i++) Card(child: ListTile(
        leading: const Icon(Icons.settings_input_component_outlined),title: Text('${rows![i].diameter} mm · ${rows![i].material}'),
        subtitle: Text('${rows![i].quantity} vorhanden · ${rows![i].printer}'),onTap: () => edit(i),
        trailing: IconButton(tooltip: 'Düse entfernen',icon: const Icon(Icons.delete_outline),onPressed: () async {
          final next = [...rows!]..removeAt(i);
          try { await saveNozzles(next); if (mounted) setState(() => rows = next); } catch (_) { if (mounted) setState(() => error = 'Düse konnte nicht entfernt werden.'); }
        }))),
    ])));
}
class _NozzleEditor extends StatefulWidget {
  const _NozzleEditor({required this.printer,this.existing});
  final String printer;
  final OwnedNozzle? existing;
  @override State<_NozzleEditor> createState() => _NozzleEditorState();
}
class _NozzleEditorState extends State<_NozzleEditor> {
  final form = GlobalKey<FormState>();
  late final diameter = TextEditingController(text: (widget.existing?.diameter ?? .4).toString());
  late final quantity = TextEditingController(text: '${widget.existing?.quantity ?? 1}');
  late String material = widget.existing?.material ?? 'Messing';
  @override void dispose() { diameter.dispose(); quantity.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AlertDialog(title: Column(crossAxisAlignment: CrossAxisAlignment.start,mainAxisSize: MainAxisSize.min,children: [
    const Text('Düse eintragen'),FilledButton(onPressed: () {
      if (!form.currentState!.validate()) return;
      Navigator.pop(context,OwnedNozzle(id: widget.existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        printer: widget.existing?.printer ?? widget.printer,diameter: double.parse(diameter.text.replaceAll(',','.')),material: material,quantity: int.parse(quantity.text)));
    },child: const Text('Speichern'))]),content: SingleChildScrollView(child: Form(key: form,child: Column(mainAxisSize: MainAxisSize.min,children: [
      Text(widget.existing?.printer ?? widget.printer),
      TextFormField(controller: diameter,decoration: const InputDecoration(labelText: 'Durchmesser in mm'),keyboardType: const TextInputType.numberWithOptions(decimal: true),
        validator: (v) { final n = double.tryParse((v ?? '').replaceAll(',','.')); return n == null || !n.isFinite || n < .1 || n > 2 ? '0,1 bis 2 mm eintragen.' : null; }),
      const SizedBox(height: 12),DropdownButtonFormField<String>(isExpanded: true,initialValue: material,decoration: const InputDecoration(labelText: 'Düsenmaterial'),
        items: ['Messing','Gehärteter Stahl','Edelstahl','Andere','Unbekannt'].map((m) => DropdownMenuItem(value: m,child: Text(m))).toList(),onChanged: (v) => material = v ?? material),
      const SizedBox(height: 12),TextFormField(controller: quantity,decoration: const InputDecoration(labelText: 'Anzahl'),keyboardType: TextInputType.number,
        validator: (v) { final n = int.tryParse(v ?? ''); return n == null || n < 0 || n > 10000 ? 'Gültige Anzahl eintragen.' : null; }),
    ]))));
}
