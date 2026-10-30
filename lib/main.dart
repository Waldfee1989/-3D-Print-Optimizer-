
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'mesh_renderer.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'app_updates.dart';
import 'filament_inventory.dart';
import 'filament_scanner.dart';
import 'project_optimizer.dart';
import 'support_analysis.dart';
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
  bool checkingForUpdate = false;
  Future<void> checkForUpdates({bool manual = false}) async {
    if (!Platform.isAndroid || !mounted || checkingForUpdate) return;
    checkingForUpdate = true;
    try {
      final installed = await PackageInfo.fromPlatform();
      final update = await findAppUpdate(int.tryParse(installed.buildNumber) ?? 0);
      if (!mounted) return;
      if (update == null) {
        if (manual) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Du verwendest bereits die aktuelle Version.')));
        return;
      }
      await showDialog<void>(context: context, barrierDismissible: false,
        builder: (_) => AppUpdateDialog(update: update));
    } catch (_) {
      // Startup remains usable without a connection; manual checks explain failures.
      if (manual && mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Updates konnten nicht geprüft werden. Bitte später erneut versuchen.')));
    } finally {
      checkingForUpdate = false;
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
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          const Text('Ersteinrichtung'),
          Wrap(spacing: 8, children: [
            TextButton(onPressed: ()=>Navigator.pop(ctx,false), child: const Text('Abbrechen')),
            FilledButton(onPressed: ()=>Navigator.pop(ctx,true), child: const Text('Speichern')),
          ]),
        ]),
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

      )));
    if (result == true) {
      setState(() { printer=pr; slicer=sl; nozzle=nz; configured=true; });
      await save();
    }
  }
  Future<void> addFilament({String barcode = '', int? index}) async {
    final p = prefs;
    if (p == null) return;
    final catalog = FilamentCatalog(p);
    final item = await showDialog<Map<String, dynamic>>(context: context,
      builder: (_) => FilamentEditor(barcode: barcode,
        profile: catalog.lookup(barcode, stock),
        existing: index == null ? null : stock[index]));
    if (item == null || !mounted) return;
    final next = [...stock];
    if (index == null) { next.add(item); } else { next[index] = item; }
    try {
      if (!await p.setString('stock', jsonEncode(next))) {
        throw const FormatException('Filamentlager konnte nicht gespeichert werden.');
      }
      if (mounted) setState(() => stock = next);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Die Rolle konnte nicht gespeichert werden. Bitte erneut versuchen.')));
      return;
    }
    try { await catalog.remember(item); }
    catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Rolle gespeichert. Die zusätzliche Barcode-Zuordnung konnte nicht gespeichert werden.')));
    }
  }

  Future<void> handleFilamentCode(String value) async {
    final code = filamentCode(value);
    if (!mounted || code.isEmpty) return;
    final matches = [for (var i = 0; i < stock.length; i++)
      if (filamentCode('${stock[i]['barcode'] ?? ''}') == code) i];
    if (matches.isNotEmpty) {
      final choice = await showDialog<int>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Barcode bereits im Lager'),
        content: SizedBox(width: double.maxFinite, child: ListView(shrinkWrap: true, children: [
          const Text('Vorhandene Rolle bearbeiten oder eine weitere Rolle hinzufügen?'),
          for (final i in matches) ListTile(
            title: Text('Rolle ${i + 1}: ${stock[i]['brand']} ${stock[i]['material']} ${stock[i]['color']}'),
            subtitle: Text('${stock[i]['grams']} g Restmenge'),
            onTap: () => Navigator.pop(ctx, i)),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, -1), child: const Text('Neue Rolle')),
        ],
      ));
      if (choice == null || !mounted) return;
      await addFilament(barcode: code, index: choice < 0 ? null : choice);
    } else {
      await addFilament(barcode: code);
    }
  }

  Future<void> scanFilament() async {
    final value = await Navigator.push<String>(context,
      MaterialPageRoute(builder: (_) => const FilamentScannerPage()));
    if (!mounted || value == null) return;
    if (value.isEmpty) { await enterCode(); }
    else { await handleFilamentCode(value); }
  }

  Future<void> enterCode() async {
    final value = await showDialog<String>(context: context,
      builder: (_) => const FilamentCodeDialog());
    if (!mounted || value == null) return;
    await handleFilamentCode(value);
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
      IconButton(tooltip:'Updates prüfen',onPressed:() => checkForUpdates(manual: true),icon:const Icon(Icons.system_update)),
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
        Card(child: ListTile(leading: const Icon(Icons.folder_open),
          title: const Text('Datei laden und Druck optimieren'),
          subtitle: const Text('STL / 3MF öffnen → Fragen beantworten → Empfehlung'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
            ModelPreviewPage(printer: printer, slicer: slicer, nozzle: nozzle, quality: qualityMode))))),
        Card(child: ListTile(leading: const Icon(Icons.folder_copy_outlined),
          title: const Text('Meine Druckprojekte'),
          subtitle: const Text('Gespeicherte Antworten und Einstellungen'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrintProjectsPage())))),
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
        const SizedBox(height: 12),
        Card(child: ListTile(
          leading: const Icon(Icons.view_in_ar),
          title: const Text('STL / 3MF öffnen'),
          subtitle: const Text('Modell ansehen und anschließend Druckteil festlegen'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => ModelPreviewPage(printer: printer, slicer: slicer, nozzle: nozzle, quality: qualityMode))),
        )),
        const SizedBox(height:12),
        const Text('Mein Filamentlager',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
        const SizedBox(height:8),
        Wrap(spacing:8,children:[
          FilledButton.icon(onPressed:scanFilament,icon:const Icon(Icons.qr_code_scanner),label:const Text('Barcode scannen')),
          OutlinedButton.icon(onPressed:enterCode,icon:const Icon(Icons.keyboard),label:const Text('Filamentcode eingeben')),
          OutlinedButton.icon(onPressed:()=>addFilament(),icon:const Icon(Icons.add),label:const Text('Manuell hinzufügen')),
        ]),
        for(var i=0;i<stock.length;i++)
          Card(child:ListTile(
            title:Text('${stock[i]['brand']} ${stock[i]['material']} ${stock[i]['color']}'),
            subtitle:Text('${stock[i]['grams']} g · Barcode: ${stock[i]['barcode']}'),
            onTap: () => addFilament(index: i),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(tooltip: 'Restmenge bearbeiten', icon: const Icon(Icons.edit),
                onPressed: () => addFilament(index: i)),
              IconButton(tooltip: 'Rolle löschen', icon:const Icon(Icons.delete_outline),onPressed:()async{
                setState(()=>stock.removeAt(i)); await save();
              }),
            ]),
          )),
        if(stock.isEmpty) const Padding(padding:EdgeInsets.all(16),
          child:Text('Noch keine Filamentrollen vorhanden.')),
        const SizedBox(height:20),
        const Text('Weitere Funktionen folgen',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
        const Text('Die Modellvorschau prüft Abmessungen und gibt bei geeigneten STL-Modellen einen Überhanghinweis. Gelenke und automatische Druckausrichtung werden noch nicht geprüft. Farbwechseloptimierung, Online-Recherche, Cloud-Synchronisierung und Slicer-Export folgen.'),
      ]),
  );
}


// Modellvorschau: lokale Dateien; keine Cloud-Uebertragung.
class _V3 {
  const _V3(this.x, this.y, this.z);
  final double x, y, z;
}

class _Triangle {
  const _Triangle(this.a, this.b, this.c);
  final _V3 a, b, c;
}

class _Mesh {
  _Mesh(this.faces, this.minimum, this.maximum, this.totalFaces);
  final List<_Triangle> faces;
  final _V3 minimum, maximum;
  final int totalFaces;
  SupportAssessment supports = const SupportAssessment('Im Slicer prüfen', 'Noch nicht geprüft.');
  late final Float32List renderVertices = _normalizedVertices();

  Float32List _normalizedVertices() {
    final center = _V3(minimum.x / 2 + maximum.x / 2,
        minimum.y / 2 + maximum.y / 2, minimum.z / 2 + maximum.z / 2);
    final extent = size;
    final radius = math.max(.001, math.sqrt(extent.x * extent.x +
        extent.y * extent.y + extent.z * extent.z) / 2);
    final result = Float32List(faces.length * 9);
    var index = 0;
    for (final face in faces) {
      for (final vertex in [face.a, face.b, face.c]) {
        result[index++] = (vertex.x - center.x) / radius;
        result[index++] = (vertex.y - center.y) / radius;
        result[index++] = (vertex.z - center.z) / radius;
      }
    }
    return result;
  }

  _V3 get size => _V3(maximum.x - minimum.x,
      maximum.y - minimum.y, maximum.z - minimum.z);
}

class _MeshReader {
  static _Mesh inBackground((String, Uint8List) input) {
    final parsed = fromBytes(input.$1, input.$2);
    // Prepare the render buffer on the worker too, before returning to the UI.
    parsed.supports = assessSupports(parsed.renderVertices, is3mf: input.$1.toLowerCase().endsWith('.3mf'));
    return parsed;
  }

  static _Mesh fromBytes(String name, Uint8List bytes) {
    if (name.toLowerCase().endsWith('.3mf')) return _from3mf(bytes);
    return _fromStl(bytes);
  }

  static _Mesh _fromStl(Uint8List bytes) {
    if (bytes.length < 15) throw const FormatException('STL-Datei ist zu klein.');
    if (bytes.length >= 84) {
      final view = ByteData.sublistView(bytes);
      final count = view.getUint32(80, Endian.little);
      if (count > 0 && 84 + count * 50 == bytes.length) {
        final all = <_Triangle>[];
        for (var i = 0; i < count; i++) {
          final pos = 84 + i * 50 + 12;
          _V3 v(int at) => _V3(view.getFloat32(at, Endian.little),
              view.getFloat32(at + 4, Endian.little),
              view.getFloat32(at + 8, Endian.little));
          all.add(_Triangle(v(pos), v(pos + 12), v(pos + 24)));
        }
        return _summarize(all);
      }
    }
    final content = utf8.decode(bytes, allowMalformed: true);
    final matches = RegExp(r'vertex\s+([-+\d.eE]+)\s+([-+\d.eE]+)\s+([-+\d.eE]+)',
        caseSensitive: false).allMatches(content);
    final vertices = <_V3>[];
    for (final m in matches) {
      vertices.add(_V3(double.parse(m[1]!), double.parse(m[2]!),
          double.parse(m[3]!)));
    }
    if (vertices.isEmpty || vertices.length % 3 != 0) {
      throw const FormatException('Keine gültigen STL-Dreiecke gefunden.');
    }
    return _summarize([
      for (var i = 0; i < vertices.length; i += 3)
        _Triangle(vertices[i], vertices[i + 1], vertices[i + 2])
    ]);
  }

  static _Mesh _from3mf(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final models = archive.files.where((f) => f.isFile &&
        f.name.toLowerCase().endsWith('.model')).toList();
    if (models.isEmpty) throw const FormatException('Keine 3MF-Modelldaten gefunden.');
    final all = <_Triangle>[];
    for (final model in models) {
      final content = model.content;
      final raw = content is List<int> ? content : <int>[];
      final doc = XmlDocument.parse(utf8.decode(raw));
      // Einfache 3MF-Meshes. Komponenten und Build-Transformationen
      // werden nicht interpretiert und duerfen nicht stillschweigend
      // als vollstaendige Druckplattenanalyse gelten.
      for (final mesh in doc.descendants.whereType<XmlElement>()
          .where((e) => e.name.local == 'mesh')) {
        final vertices = <_V3>[];
        for (final v in mesh.descendants.whereType<XmlElement>()
            .where((e) => e.name.local == 'vertex')) {
          double coord(String n) => double.parse(v.getAttribute(n) ?? '0');
          vertices.add(_V3(coord('x'), coord('y'), coord('z')));
        }
        for (final t in mesh.descendants.whereType<XmlElement>()
            .where((e) => e.name.local == 'triangle')) {
          final a = int.parse(t.getAttribute('v1') ?? '-1');
          final b = int.parse(t.getAttribute('v2') ?? '-1');
          final c = int.parse(t.getAttribute('v3') ?? '-1');
          if (a < 0 || b < 0 || c < 0 ||
              a >= vertices.length || b >= vertices.length || c >= vertices.length) {
            throw const FormatException('3MF enthält ungültige Eckpunkte.');
          }
          all.add(_Triangle(vertices[a], vertices[b], vertices[c]));
        }
      }
    }
    if (all.isEmpty) throw const FormatException('Keine 3MF-Dreiecke gefunden.');
    return _summarize(all);
  }

  static _Mesh _summarize(List<_Triangle> all) {
    if (all.isEmpty) throw const FormatException('Leeres Modell.');
    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity,
        maxZ = double.negativeInfinity;
    for (final t in all) {
      for (final v in [t.a, t.b, t.c]) {
        if (!v.x.isFinite || !v.y.isFinite || !v.z.isFinite) {
          throw const FormatException('Ungültige Modellkoordinaten.');
        }
        minX = math.min(minX, v.x); maxX = math.max(maxX, v.x);
        minY = math.min(minY, v.y); maxY = math.max(maxY, v.y);
        minZ = math.min(minZ, v.z); maxZ = math.max(maxZ, v.z);
      }
    }
    return _Mesh(all, _V3(minX, minY, minZ),
        _V3(maxX, maxY, maxZ), all.length);
  }
}

class ModelPreviewPage extends StatefulWidget {
  const ModelPreviewPage({super.key, this.printer = 'Anycubic Kobra S1',
    this.slicer = 'Anycubic Slicer Next', this.nozzle = '0.4', this.quality = 'Maximale Qualität'});
  final String printer, slicer, nozzle, quality;
  @override State<ModelPreviewPage> createState() => _ModelPreviewPageState();
}

class _ModelPreviewPageState extends State<ModelPreviewPage> {
  _Mesh? mesh;
  String? fileName, error;
  String projectId = DateTime.now().microsecondsSinceEpoch.toString();
  bool loading = false;
  double angleX = 25, angleY = 30, zoom = 1;
  final Map<int, Offset> _touches = {};
  double _gestureZoom = 1, _gestureSpan = 0;

  double _wrapAngle(double value) => (value + 180) % 360 - 180;

  double get _touchSpan {
    if (_touches.length < 2) return 0;
    final points = _touches.values.take(2).toList();
    return (points[0] - points[1]).distance;
  }

  void _startTouch(PointerDownEvent event) {
    _touches[event.pointer] = event.localPosition;
    _gestureZoom = zoom;
    _gestureSpan = _touchSpan;
  }

  void _moveTouch(PointerMoveEvent event) {
    final previous = _touches[event.pointer];
    if (previous == null) return;
    _touches[event.pointer] = event.localPosition;
    setState(() {
      if (_touches.length == 1) {
        final delta = event.localPosition - previous;
        angleY = _wrapAngle(angleY + delta.dx * .5);
        angleX = _wrapAngle(angleX + delta.dy * .5);
      } else if (_gestureSpan > 0) {
        zoom = (_gestureZoom * _touchSpan / _gestureSpan).clamp(.25, 5.0).toDouble();
      }
    });
  }

  void _endTouch(PointerEvent event) {
    _touches.remove(event.pointer);
    _gestureZoom = zoom;
    _gestureSpan = _touchSpan;
  }

  Future<void> openModel() async {
    setState(() { loading = true; error = null; });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['stl', '3mf'],
        withData: false,
      );
      if (result == null) return;
      final file = result.files.single;
      const maximumBytes = 100 * 1024 * 1024;
      // Check metadata before loading the entire file into memory.
      if (file.size > maximumBytes || (file.path != null &&
          await File(file.path!).length() > maximumBytes)) {
        throw const FormatException('Datei ist größer als 100 MB.');
      }
      final bytes = file.bytes ?? (file.path == null ? null :
          await File(file.path!).readAsBytes());
      if (bytes == null) throw const FormatException('Datei konnte nicht gelesen werden.');
      // Schutz vor sehr grossen Dateien auf Mobilgeraeten.
      if (bytes.length > maximumBytes) {
        throw const FormatException('Datei ist größer als 100 MB.');
      }
      final parsed = await compute(_MeshReader.inBackground, (file.name, bytes));
      if (!mounted) return;
      setState(() { mesh = parsed; fileName = file.name; projectId = DateTime.now().microsecondsSinceEpoch.toString(); angleX = 25; angleY = 30; zoom = 1; });
    } catch (e) {
      if (mounted) setState(() => error = 'Datei konnte nicht geöffnet werden: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override Widget build(BuildContext context) {
    final m = mesh;
    return Scaffold(
      appBar: AppBar(title: const Text('3D-Modellvorschau'), actions: [
        TextButton(onPressed: m == null || loading ? null : () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => ProjectOptimizerPage(project: PrintProject(
            id: projectId, fileName: fileName ?? 'Modell',
            dimensions: '${m.size.x.toStringAsFixed(1)} × ${m.size.y.toStringAsFixed(1)} × ${m.size.z.toStringAsFixed(1)} (Modellkoordinaten, normalerweise mm)',
            printer: widget.printer, slicer: widget.slicer, nozzle: widget.nozzle,
            priority: widget.quality, supportStatus: m.supports.status, supportReason: m.supports.reason)))), child: const Text('OK')),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        FilledButton.icon(onPressed: loading ? null : openModel,
          icon: const Icon(Icons.folder_open),
          label: Text(loading ? 'Datei wird geladen...' : 'STL / 3MF auswählen')),
        if (error != null) Padding(padding: const EdgeInsets.all(12),
          child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (m != null) ...[
          const SizedBox(height: 12),
          Text(fileName ?? 'Modell', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Container(height: 300, decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12)),
            child: ClipRRect(borderRadius: BorderRadius.circular(12),
              child: RawGestureDetector(
                // Claim touches inside the preview so vertical rotation does
                // not become a ListView scroll. Scrolling outside still works.
                gestures: {
                  EagerGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                      () => EagerGestureRecognizer(), (_) {}),
                },
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _startTouch,
                  onPointerMove: _moveTouch,
                  onPointerUp: _endTouch,
                  onPointerCancel: _endTouch,
                child: LayoutBuilder(builder: (context, constraints) {
                  // Bound raster work while retaining the viewport aspect ratio.
                  final factor = math.min(1.0, 480 / math.max(
                      constraints.maxWidth, constraints.maxHeight));
                  return _SurfacePreview(mesh: m, angleX: angleX, angleY: angleY,
                    zoom: zoom, width: math.max(1, (constraints.maxWidth * factor).round()),
                    height: math.max(1, (constraints.maxHeight * factor).round()));
                }))))),
          const SizedBox(height: 8),
          const Text('Mit einem Finger drehen · Mit zwei Fingern zoomen'),
          Text('Zoom: ${(zoom * 100).round()} %'),
          Slider(value: zoom, min: .25, max: 5,
            onChanged: (v) => setState(() => zoom = v)),
          const SizedBox(height: 12),
          Text('Horizontal drehen: ${angleY.round()}°'),
          Slider(value: angleY, min: -180, max: 180,
            onChanged: (v) => setState(() => angleY = v)),
          Text('Vertikal drehen: ${angleX.round()}°'),
          Slider(value: angleX, min: -180, max: 180,
            onChanged: (v) => setState(() => angleX = v)),
          OutlinedButton(onPressed: () => setState(() { angleX = 25; angleY = 30; zoom = 1; }),
            child: const Text('Ansicht zurücksetzen')),
          const SizedBox(height: 8),
          Text('Abmessungen (Modellkoordinaten, normalerweise mm): '
            '${m.size.x.toStringAsFixed(1)} × ${m.size.y.toStringAsFixed(1)} × '
            '${m.size.z.toStringAsFixed(1)}'),
          Text('Dreiecke: ${m.totalFaces}'),
          Text('Stützen: ${m.supports.status}'),
          Text(m.supports.reason),
          const Text('Bewertung für die Dateiausrichtung. Drehen in der Vorschau ändert die Druckausrichtung nicht.'),
          const SizedBox(height: 12),
          const Text('Hinweis: Dies ist eine einfache drehbare Geometrievorschau. '
            'Bei 3MF werden Komponenten, Farbzuweisungen und Transformationen '
            'noch nicht vollständig ausgewertet. Die Ansicht verändert nicht '
            'die Originaldatei. Vollständige Druckbarkeit und Passgenauigkeit werden noch '
            'nicht automatisch geprüft.'),
        ] else if (!loading) ...[
          const SizedBox(height: 32),
          const Icon(Icons.view_in_ar, size: 64),
          const SizedBox(height: 12),
          const Center(child: Text('Öffne eine STL- oder 3MF-Datei.')),
        ],
      ]),
    );
  }
}

class _SurfacePreview extends StatefulWidget {
  const _SurfacePreview({required this.mesh, required this.angleX,
    required this.angleY, required this.zoom, required this.width, required this.height});
  final _Mesh mesh;
  final double angleX, angleY, zoom;
  final int width, height;

  @override State<_SurfacePreview> createState() => _SurfacePreviewState();
}

class _SurfacePreviewState extends State<_SurfacePreview> {
  ui.Image? _image;
  String? _error;
  int _revision = 0;
  bool _rendering = false;

  @override void initState() { super.initState(); _requestRender(); }

  @override void didUpdateWidget(covariant _SurfacePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mesh != widget.mesh || oldWidget.angleX != widget.angleX ||
        oldWidget.angleY != widget.angleY || oldWidget.zoom != widget.zoom ||
        oldWidget.width != widget.width || oldWidget.height != widget.height) {
      _requestRender();
    }
  }

  void _requestRender() {
    _revision++;
    if (!_rendering) unawaited(_render());
  }

  Future<void> _render() async {
    _rendering = true;
    try {
      while (mounted) {
        final revision = _revision;
        final mesh = widget.mesh;
        final request = MeshRenderRequest(widget.mesh.renderVertices,
            widget.width, widget.height, widget.angleX, widget.angleY, widget.zoom);
        final pixels = await compute(renderMesh, request);
        if (!mounted) return;
        if (mesh != widget.mesh) continue;
        final completer = Completer<ui.Image>();
        ui.decodeImageFromPixels(pixels, request.width, request.height,
            ui.PixelFormat.rgba8888, completer.complete);
        final image = await completer.future;
        if (!mounted || mesh != widget.mesh) {
          image.dispose();
          if (!mounted) return;
          continue;
        }
        final previous = _image;
        setState(() { _image = image; _error = null; });
        if (previous != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
        }
        if (revision == _revision) break;
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Vorschau konnte nicht berechnet werden.');
    } finally {
      _rendering = false;
    }
  }

  @override void dispose() { _image?.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) => RepaintBoundary(
    child: Stack(fit: StackFit.expand, children: [
      if (_image != null) RawImage(image: _image, fit: BoxFit.fill,
        filterQuality: FilterQuality.medium),
      if (_image == null && _error == null)
        const Center(child: CircularProgressIndicator()),
      if (_error != null) Center(child: Text(_error!)),
    ]));
}
