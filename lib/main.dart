
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
        const SizedBox(height: 12),
        Card(child: ListTile(
          leading: const Icon(Icons.view_in_ar),
          title: const Text('STL / 3MF öffnen'),
          subtitle: const Text('Modell ansehen, drehen und Abmessungen prüfen'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const ModelPreviewPage())),
        )),
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
        const Text('Die Modellvorschau prüft Abmessungen, aber noch keine Überhänge, Gelenke oder automatische Ausrichtung. Farbwechseloptimierung, Online-Recherche, Cloud-Synchronisierung und Slicer-Export folgen.'),
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
  const ModelPreviewPage({super.key});
  @override State<ModelPreviewPage> createState() => _ModelPreviewPageState();
}

class _ModelPreviewPageState extends State<ModelPreviewPage> {
  _Mesh? mesh;
  String? fileName, error;
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
        withData: true,
      );
      if (result == null) return;
      final file = result.files.single;
      final bytes = file.bytes ?? (file.path == null ? null :
          await File(file.path!).readAsBytes());
      if (bytes == null) throw const FormatException('Datei konnte nicht gelesen werden.');
      // Schutz vor sehr grossen Dateien auf Mobilgeraeten.
      if (bytes.length > 30 * 1024 * 1024) {
        throw const FormatException('Datei ist größer als 30 MB.');
      }
      final parsed = _MeshReader.fromBytes(file.name, bytes);
      if (!mounted) return;
      setState(() { mesh = parsed; fileName = file.name; angleX = 25; angleY = 30; zoom = 1; });
    } catch (e) {
      if (mounted) setState(() => error = 'Datei konnte nicht geöffnet werden: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override Widget build(BuildContext context) {
    final m = mesh;
    return Scaffold(
      appBar: AppBar(title: const Text('3D-Modellvorschau')),
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
          const SizedBox(height: 12),
          const Text('Hinweis: Dies ist eine einfache drehbare Geometrievorschau. '
            'Bei 3MF werden Komponenten, Farbzuweisungen und Transformationen '
            'noch nicht vollständig ausgewertet. Die Ansicht verändert nicht '
            'die Originaldatei. Druckbarkeit und Passgenauigkeit werden noch '
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
