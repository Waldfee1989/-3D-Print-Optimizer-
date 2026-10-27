
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() => runApp(const OptimizerApp());

class OptimizerApp extends StatelessWidget {
  const OptimizerApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    title: '3D Print Optimizer',
    theme: ThemeData(colorSchemeSeed: Colors.blue, brightness: Brightness.dark, useMaterial3: true),
    home: const HomePage(),
  );
}
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override State<HomePage> createState() => _HomePageState();
}
class _HomePageState extends State<HomePage> {
  SharedPreferences? prefs;
  String printer = 'Anycubic Kobra S1', slicer = 'Anycubic Slicer', nozzle = '0.4';
  bool configured = false;
  List<Map<String, dynamic>> stock = [];
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      prefs = p; configured = p.getBool('configured') ?? false;
      printer = p.getString('printer') ?? printer;
      slicer = p.getString('slicer') ?? slicer;
      nozzle = p.getString('nozzle') ?? nozzle;
      try {
        stock = (jsonDecode(p.getString('stock') ?? '[]') as List)
            .map((e) => Map<String,dynamic>.from(e as Map)).toList();
      } catch (_) { stock = []; }
    });
  }
  Future<void> save() async {
    final p = prefs; if (p == null) return;
    await p.setBool('configured', configured);
    await p.setString('printer', printer);
    await p.setString('slicer', slicer);
    await p.setString('nozzle', nozzle);
    await p.setString('stock', jsonEncode(stock));
  }
  Future<void> setup() async {
    String pr = printer, sl = slicer, nz = nozzle;
    final result = await showDialog<bool>(context: context, builder: (ctx) =>
      StatefulBuilder(builder: (ctx, update) => AlertDialog(
        title: const Text('Ersteinrichtung'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Drucker, Slicer und Düse auswählen. Später änderbar.'),
          TextField(controller: TextEditingController(text: pr),
            decoration: const InputDecoration(labelText: 'Druckermodell'),
            onChanged: (v) => pr=v),
          DropdownButtonFormField<String>(value: sl, decoration: const InputDecoration(labelText: 'Slicer'),
            items: ['Anycubic Slicer','Anycubic Slicer Next','OrcaSlicer','Anderer Slicer']
              .map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),
            onChanged: (v)=>update(()=>sl=v??sl)),
          DropdownButtonFormField<String>(value: nz, decoration: const InputDecoration(labelText: 'Düse (mm)'),
            items: ['0.2','0.4','0.6','0.8'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),
            onChanged: (v)=>update(()=>nz=v??nz)),
        ])),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(ctx,false), child: const Text('Abbrechen')),
          FilledButton(onPressed: ()=>Navigator.pop(ctx,true), child: const Text('Speichern')),
        ],
      )));
    if (result == true) {
      setState(() { printer=pr; slicer=sl; nozzle=nz; configured=true; });
      await save();
    }
  }
  Future<void> addFilament({String barcode = ''}) async {
    final brand = TextEditingController(), material = TextEditingController(text:'PLA');
    final color = TextEditingController(), grams = TextEditingController(text:'1000');
    final code = TextEditingController(text:barcode);
    final ok = await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Filament hinzufügen'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        for(final field in <(TextEditingController,String)>[
          (code,'Barcode'),(brand,'Hersteller'),(material,'Material'),(color,'Farbe'),(grams,'Restmenge (g)')
        ]) TextField(controller:field.$1,decoration:InputDecoration(labelText:field.$2),
          keyboardType: field.$2.startsWith('Restmenge') ? TextInputType.number : TextInputType.text),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Abbrechen')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Hinzufügen'))],
    ));
    if(ok==true) {
      setState(()=>stock.add({'barcode':code.text.trim(),'brand':brand.text.trim(),
        'material':material.text.trim(),'color':color.text.trim(),
        'grams':double.tryParse(grams.text.replaceAll(',','.'))??0}));
      await save();
    }
    for(final c in [brand,material,color,grams,code]) { c.dispose(); }
  }
  Future<void> scan() async {
    if (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Kamera-Scanner ist für Android vorgesehen. Bitte manuell hinzufügen.')));
      return;
    }
    String? scanned;
    scanned = await Navigator.push<String>(context,MaterialPageRoute(builder:(ctx)=>Scaffold(
      appBar:AppBar(title:const Text('Barcode scannen')),
      body:MobileScanner(onDetect:(capture) {
        if(capture.barcodes.isNotEmpty) {
          final value=capture.barcodes.first.rawValue;
          if(value!=null && Navigator.canPop(ctx)) Navigator.pop(ctx,value);
        }
      }),
    )));
    if(scanned==null || !mounted) return;
    final existing=stock.where((x)=>x['barcode']==scanned).toList();
    if(existing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(
        'Bekannte Rolle: ${existing.first['brand']} ${existing.first['material']} – ${existing.first['grams']} g')));
    } else {
      await addFilament(barcode:scanned);
    }
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar:AppBar(title:const Text('3D Print Optimizer'),actions:[
      IconButton(tooltip:'Einrichtung',onPressed:setup,icon:const Icon(Icons.settings)),
    ]),
    body:prefs==null ? const Center(child:CircularProgressIndicator()) :
      ListView(padding:const EdgeInsets.all(16),children:[
        if(!configured) Card(child:ListTile(
          title:const Text('Einrichtung starten'),
          subtitle:const Text('Drucker und Slicer einmal festlegen'),
          trailing:const Icon(Icons.arrow_forward),onTap:setup)),
        Card(child:ListTile(title:Text(printer),
          subtitle:Text('$slicer · Düse $nozzle mm'),leading:const Icon(Icons.print))),
        const SizedBox(height:12),
        const Text('Mein Filamentlager',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
        const SizedBox(height:8),
        Wrap(spacing:8,children:[
          FilledButton.icon(onPressed:scan,icon:const Icon(Icons.qr_code_scanner),label:const Text('Barcode scannen')),
          OutlinedButton.icon(onPressed:()=>addFilament(),icon:const Icon(Icons.add),label:const Text('Manuell hinzufügen')),
        ]),
        for(var i=0;i<stock.length;i++)
          Card(child:ListTile(
            title:Text('${stock[i]['brand']} ${stock[i]['material']} ${stock[i]['color']}'),
            subtitle:Text('${stock[i]['grams']} g · Barcode: ${stock[i]['barcode']}'),
            trailing:IconButton(icon:const Icon(Icons.delete_outline),onPressed:()async{
              setState(()=>stock.removeAt(i)); await save();
            }),
          )),
        if(stock.isEmpty) const Padding(padding:EdgeInsets.all(16),
          child:Text('Noch keine Filamentrollen vorhanden.')),
        const SizedBox(height:20),
        const Text('Weitere Funktionen folgen',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
        const Text('STL-/3MF-Analyse, Cloud-Synchronisierung, Online-Recherche und Slicer-Export sind in diesem Starter noch nicht implementiert.'),
      ]),
  );
}
