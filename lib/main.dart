
import 'dart:convert';
import 'dart:io';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  String printer = 'Anycubic Kobra S1', slicer = 'Anycubic Slicer Next', nozzle = '0.4';
  bool configured = false;
  String qualityMode = 'Maximale Qualität';
  List<Map<String, dynamic>> stock = [];
  @override void initState() { super.initState(); load(); WidgetsBinding.instance.addPostFrameCallback((_) => checkForUpdates()); }
  Future<void> checkForUpdates() async {
    if (!Platform.isAndroid || !mounted) return;
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
      final request = await client.getUrl(Uri.parse(
        'https://api.github.com/repos/Waldfee1989/-3D-Print-Optimizer-/releases/latest'));
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      request.headers.set(HttpHeaders.userAgentHeader, '3D-Print-Optimizer');
      final response = await request.close();
      if (response.statusCode != 200) return;
      final data = jsonDecode(await response.transform(utf8.decoder).join()) as Map<String, dynamic>;
      final match = RegExp(r'(?i)build-(\d+)').firstMatch((data['tag_name'] ?? '').toString());
      if (match == null) return;
      final remoteBuild = int.tryParse(match.group(1)!) ?? 0;
      final installed = await PackageInfo.fromPlatform();
      final installedBuild = int.tryParse(installed.buildNumber) ?? 0;
      if (remoteBuild <= installedBuild || !mounted) return;
      final assets = data['assets'] as List? ?? [];
      final apk = assets.whereType<Map>().where((a) => a['name'] == 'app-release.apk').toList();
      if (apk.isEmpty) return;
      final url = Uri.tryParse((apk.first['browser_download_url'] ?? '').toString());
      if (url == null || url.scheme != 'https') return;
      final accept = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Update verfügbar'),
        content: Text('Build $remoteBuild ist verfügbar. Installiert: Build $installedBuild.\n\nAPK herunterladen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Später')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Herunterladen')),
        ],
      ));
      if (accept == true) await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Die App funktioniert auch ohne Internet.
    } finally {
      client?.close(force: true);
    }
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      prefs = p; configured = p.getBool('configured') ?? false;
      printer = p.getString('printer') ?? printer;
      slicer = p.getString('slicer') ?? slicer;
      nozzle = p.getString('nozzle') ?? nozzle;
      qualityMode = p.getString('qualityMode') ?? qualityMode;
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
    await p.setString('qualityMode', qualityMode);
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
  Future<void> enterCode() async {
    final code = TextEditingController();
    final value = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Filamentcode eingeben'),
      content: TextField(controller: code, autofocus: true,
        decoration: const InputDecoration(labelText: 'Code auf der Rolle'),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim())),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () => Navigator.pop(ctx, code.text.trim()), child: const Text('Suchen')),
      ],
    ));
    code.dispose();
    if (!mounted || value == null || value.isEmpty) return;
    final found = stock.where((e) => (e['barcode'] ?? '').toString().toLowerCase() == value.toLowerCase()).toList();
    if (found.isNotEmpty) {
      final item = found.first;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        'Bekannt: ${item['brand']} ${item['material']} ${item['color']} – ${item['grams']} g')));
    } else {
      await addFilament(barcode: value);
    }
  }

  Map<String, String> get profile {
    switch (qualityMode) {
      case 'Ausgewogen':
        return {'Schichthöhe': '0,16 mm', 'Außenwand': '50 mm/s',
          'Wände': '3', 'Infill': '15 %', 'Oberfläche': 'Standard'};
      case 'Schneller Druck':
        return {'Schichthöhe': '0,24 mm', 'Außenwand': '80 mm/s',
          'Wände': '2', 'Infill': '12 %', 'Oberfläche': 'Geschwindigkeit'};
      default:
        return {'Schichthöhe': '0,12 mm', 'Außenwand': '35 mm/s',
          'Wände': '3', 'Infill': '15 %', 'Oberfläche': 'Feine Details'};
    }
  }

  Future<void> showProfile() async {
    await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: Text('PLA · $qualityMode'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$printer · $slicer · Düse $nozzle mm'),
          const SizedBox(height: 12),
          for (final entry in profile.entries) Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text('${entry.key}: ${entry.value}')),
          const SizedBox(height: 12),
          const Text('Startwerte für PLA mit 0,4-mm-Düse. Temperatur, Kühlung, '
            'Haftung und Beschleunigung müssen mit Filament- und Druckerprofil '
            'abgeglichen werden. Noch keine STL-/3MF-Modellanalyse oder '
            'Slicer-Übertragung.'),
        ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen'))],
    ));
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar:AppBar(title:const Text('3D Print Optimizer'),actions:[
      IconButton(tooltip:'Updates prüfen',onPressed:checkForUpdates,icon:const Icon(Icons.system_update)),
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
        const SizedBox(height: 12),
        const Text('Druckoptimierung', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            DropdownButtonFormField<String>(
              value: qualityMode,
              decoration: const InputDecoration(labelText: 'Druckmodus'),
              items: ['Maximale Qualität', 'Ausgewogen', 'Schneller Druck']
                .map((mode) => DropdownMenuItem(value: mode, child: Text(mode))).toList(),
              onChanged: (value) async {
                if (value == null) return;
                setState(() => qualityMode = value);
                await save();
              },
            ),
            const SizedBox(height: 8),
            Text('PLA · Schichthöhe ${profile['Schichthöhe']} · Außenwand ${profile['Außenwand']}'),
            const SizedBox(height: 8),
            FilledButton.icon(onPressed: showProfile,
              icon: const Icon(Icons.tune), label: const Text('Einstellungen anzeigen')),
          ],
        ))),
        const SizedBox(height:12),
        const Text('Mein Filamentlager',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
        const SizedBox(height:8),
        Wrap(spacing:8,children:[
          FilledButton.icon(onPressed:enterCode,icon:const Icon(Icons.keyboard),label:const Text('Filamentcode eingeben')),
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
        const Text('STL-/3MF-Analyse, automatische Ausrichtung, Farbwechseloptimierung, Online-Recherche, Cloud-Synchronisierung und Slicer-Export sind noch nicht implementiert.'),
      ]),
  );
}

