import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const printerBedsKey = 'printer_beds_v1';
class PrinterBed {
  const PrinterBed(this.width,this.depth,this.height);
  final double width,depth,height;
  bool get valid => [width,depth,height].every((n) => n.isFinite && n >= 10 && n <= 2000);
  Map<String,double> toJson() => {'width': width,'depth': depth,'height': height};
  factory PrinterBed.fromJson(Map<String,dynamic> data) => PrinterBed(
    (data['width'] as num).toDouble(),(data['depth'] as num).toDouble(),(data['height'] as num).toDouble());
}
// Official S1 system profile printable_area / printable_height:
// https://github.com/ANYCUBIC-3D/AnycubicSlicerNext/tree/main/resources/profiles/Anycubic/machine
PrinterBed? knownPrinterBed(String printer) => ['anycubic kobra s1','kobra s1'].contains(printer.trim().toLowerCase())
  ? const PrinterBed(250,250,250) : null;
PrinterBed? loadPrinterBed(SharedPreferences prefs,String printer) {
  try {
    final map = jsonDecode(prefs.getString(printerBedsKey) ?? '{}') as Map;
    final raw = map[printer.trim().toLowerCase()];
    if (raw is Map) {
      final bed = PrinterBed.fromJson(Map<String,dynamic>.from(raw));
      if (bed.valid) return bed;
    }
  } catch (_) { /* Unknown hardware is never assigned guessed dimensions. */ }
  return knownPrinterBed(printer);
}
Future<void> savePrinterBed(SharedPreferences prefs,String printer,PrinterBed bed) async {
  if (!bed.valid) throw const FormatException('Ungültiger Bauraum.');
  final map = Map<String,dynamic>.from(jsonDecode(prefs.getString(printerBedsKey) ?? '{}') as Map);
  map[printer.trim().toLowerCase()] = bed.toJson();
  if (!await prefs.setString(printerBedsKey,jsonEncode(map))) throw const FormatException('Bauraum konnte nicht gespeichert werden.');
}
class PrinterSetup {
  const PrinterSetup(this.printer,this.slicer,this.nozzle,this.bed);
  final String printer,slicer,nozzle;
  final PrinterBed bed;
}
class PrinterSetupPage extends StatefulWidget {
  const PrinterSetupPage({super.key,required this.printer,required this.slicer,required this.nozzle,this.bed});
  final String printer,slicer,nozzle;
  final PrinterBed? bed;
  @override State<PrinterSetupPage> createState() => _PrinterSetupPageState();
}
class _PrinterSetupPageState extends State<PrinterSetupPage> {
  final form = GlobalKey<FormState>();
  late final printer = TextEditingController(text: widget.printer);
  late final width = TextEditingController(text: widget.bed?.width.toStringAsFixed(0) ?? '');
  late final depth = TextEditingController(text: widget.bed?.depth.toStringAsFixed(0) ?? '');
  late final height = TextEditingController(text: widget.bed?.height.toStringAsFixed(0) ?? '');
  late String slicer = widget.slicer,nozzle = widget.nozzle;
  double? number(String? text) => double.tryParse((text ?? '').replaceAll(',','.'));
  @override void dispose() { for (final c in [printer,width,depth,height]) { c.dispose(); } super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Drucker einrichten'),actions: [
    TextButton(onPressed: () {
      if (!form.currentState!.validate()) return;
      Navigator.pop(context,PrinterSetup(printer.text.trim(),slicer,nozzle,PrinterBed(number(width.text)!,number(depth.text)!,number(height.text)!)));
    },child: const Text('Speichern'))]),body: SafeArea(top: false,child: Form(key: form,child: ListView(
      padding: const EdgeInsets.all(16),children: [
        TextFormField(controller: printer,decoration: const InputDecoration(labelText: 'Druckermodell'),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Druckermodell eintragen.' : null,
          onChanged: (value) {
            final bed = knownPrinterBed(value);
            width.text = bed?.width.toStringAsFixed(0) ?? ''; depth.text = bed?.depth.toStringAsFixed(0) ?? ''; height.text = bed?.height.toStringAsFixed(0) ?? '';
          }),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(isExpanded: true,initialValue: slicer,decoration: const InputDecoration(labelText: 'Slicer'),
          items: ['Anycubic Slicer','Anycubic Slicer Next','OrcaSlicer','Anderer Slicer'].map((s) => DropdownMenuItem(value: s,child: Text(s))).toList(),
          onChanged: (v) => slicer = v ?? slicer),
        const SizedBox(height: 16),
        TextFormField(initialValue: nozzle,decoration: const InputDecoration(labelText: 'Eingebaute Düse in mm'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),onChanged: (v) => nozzle = v.replaceAll(',','.'),
          validator: (v) { final n = number(v); return n == null || !n.isFinite || n < .1 || n > 2 ? 'Düse zwischen 0,1 und 2 mm eintragen.' : null; }),
        const SizedBox(height: 24),
        const Text('Bauraum des Druckers',style: TextStyle(fontSize: 20,fontWeight: FontWeight.bold)),
        const Text('Herstellermaße verwenden. Die Druckplatte und alle Teile werden damit geprüft.'),
        const SizedBox(height: 12),
        for (final field in [(width,'Breite X in mm'),(depth,'Tiefe Y in mm'),(height,'Höhe Z in mm')]) Padding(
          padding: const EdgeInsets.only(bottom: 12),child: TextFormField(controller: field.$1,
            decoration: InputDecoration(labelText: field.$2),keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) { final n = number(v); return n == null || !n.isFinite || n < 10 || n > 2000 ? 'Maß zwischen 10 und 2000 mm eintragen.' : null; })),
      ]))));
}
