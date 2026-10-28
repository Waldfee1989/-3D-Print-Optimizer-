import 'dart:convert';
import 'dart:io';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
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
      final tag = (data['tag_name'] ?? '').toString();
      final match = RegExp(r'(?i)build-(\d+)').firstMatch(tag);
      if (match == null) return;
      final remoteBuild = int.tryParse(match.group(1)!) ?? 0;
      final installed = await PackageInfo.fromPlatform();
      final installedBuild = int.tryParse(installed.buildNumber) ?? 0;
      if (remoteBuild <= installedBuild || !mounted) return;
      final assets = (data['assets'] as List? ?? []);
      final apk = assets.whereType<Map>().where((a) =>
        a['name'] == 'app-release.apk').toList();
      if (apk.isEmpty) return;
      final url = Uri.tryParse((apk.first['browser_download_url'] ?? '').toString());
      if (url == null || url.scheme != 'https') return;
      final update = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Update verfügbar'),
        content: Text('Build $remoteBuild ist verfügbar. Installiert: Build $installedBuild.\n\nAPK herunterladen und Android-Installation öffnen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Später')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Herunterladen')),
        ],
      ));
      if (update == true) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      // Ohne Internet kann die App normal weiterverwendet werden.
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
          const Text('Drucker, Slicer und Düse ausw��hlen. Später änderbar.'),
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
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Hinzuf��gen'))],
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
    final scanned = await Navigator.push<String>(context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()));
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
          subtitle:Text('$slicer – Düse $nozzle mm'),leading:const Icon(Icons.print))),
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
            subtitle:Text('${stock[i]['grams']} g – Barcode: ${stock[i]['barcode']}'),
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


class BarcodeScannerPage extends StatefulWidget {
  const BarcodeScannerPage({super.key});
  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage>
    with WidgetsBindingObserver {
  MobileScannerController? _controller;
  bool _processing = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _newController();
  }

  void _newController() {
    final previous = _controller;
    _generation++;
    _processing = false;
    _controller = MobileScannerController(
      autoStart: true,
      facing: CameraFacing.back,
      detectionSpeed: DetectionSpeed.noDuplicates,
      formats: const [BarcodeFormat.ean13, BarcodeFormat.ean8,
        BarcodeFormat.upcA, BarcodeFormat.upcE, BarcodeFormat.qrCode,
        BarcodeFormat.code128],
    );
    if (previous != null) {
      previous.dispose();
    }
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null) return;
    if (state == AppLifecycleState.resumed) {
      controller.start().catchError((Object _) {});
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      controller.stop().catchError((Object _) {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _manual() async {
    final text = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Barcode manuell eingeben'),
        content: TextField(controller: text, autofocus: true,
          keyboardType: TextInputType.text,
          decoration: const InputDecoration(labelText: 'EAN, UPC oder QR-Code')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, text.text.trim()),
            child: const Text('Übernehmen')),
        ],
      ),
    );
    text.dispose();
    if (mounted && result != null && result.isNotEmpty) {
      Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
    return Scaffold(
      appBar: AppBar(title: const Text('Barcode scannen'), actions: [
        IconButton(tooltip: 'Scanner neu starten', onPressed: _newController,
          icon: const Icon(Icons.refresh)),
      ]),
      body: Column(children: [
        Expanded(child: MobileScanner(
          key: ValueKey(_generation),
          controller: controller,
          onDetect: (capture) {
            if (_processing || capture.barcodes.isEmpty) return;
            final value = capture.barcodes.first.rawValue;
            if (value == null || value.trim().isEmpty) return;
            _processing = true;
            if (mounted) Navigator.pop(context, value.trim());
          },
          errorBuilder: (context, error, child) => Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              const Text('Kamera konnte nicht gestartet werden.',
                textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(error.toString(), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _newController,
                child: const Text('Erneut versuchen')),
            ]),
          )),
        )),
        SafeArea(top: false, child: Padding(
          padding: const EdgeInsets.all(12),
          child: OutlinedButton.icon(onPressed: _manual,
            icon: const Icon(Icons.keyboard),
            label: const Text('Barcode manuell eingeben')),
        )),
      ]),
    );
  }
}
