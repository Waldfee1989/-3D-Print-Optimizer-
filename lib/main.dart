
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
import 'package:package_info_plus/package_info_plus.dart';
import 'app_updates.dart';
import 'filament_inventory.dart';
import 'filament_scanner.dart';
import 'project_optimizer.dart';
import 'support_analysis.dart';
import 'model_3mf.dart';
import 'print_geometry.dart';
import 'model_size_dialog.dart';
import 'build_plate.dart';
import 'printer_setup.dart';
import 'nozzles.dart';
import 'low_stock.dart';
import 'help_chat.dart';
import 'model_cut.dart';
import 'app_design.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  LicenseRegistry.addLicense(() async* { yield LicenseEntryWithLineBreaks(['Manifold'],await rootBundle.loadString('assets/licenses/Manifold.txt')); });
  runApp(const OptimizerApp());
}

Future<(String,Uint8List)?> chooseModelBytes() async {
  final result = await FilePicker.platform.pickFiles(type: FileType.custom,
    allowedExtensions: ['stl','3mf'],withData: false);
  if (result == null) return null;
  final file = result.files.single;
  const maximum = 100*1024*1024;
  if (file.size > maximum || (file.path != null && await File(file.path!).length() > maximum))
    throw const FormatException('Datei ist größer als 100 MB.');
  final bytes = file.bytes ?? (file.path == null ? null : await File(file.path!).readAsBytes());
  if (bytes == null) throw const FormatException('Datei konnte nicht gelesen werden.');
  if (bytes.length > maximum) throw const FormatException('Datei ist größer als 100 MB.');
  return (file.name,bytes);
}
Future<PlatePart?> pickPlatePart() async {
  final input = await chooseModelBytes();
  return input == null ? null : compute(_MeshReader.plateInBackground,input);
}

class OptimizerApp extends StatelessWidget {
  const OptimizerApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    title: '3D Print Optimizer',
    debugShowCheckedModeBanner: false,
    theme: studioTheme(),
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
  PrinterBed? bed;
  double lowStockThreshold = 200;
  bool configured = false;
  bool inventoryOpen = false;
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
      bed = loadPrinterBed(p,printer);
      lowStockThreshold = p.getDouble(lowStockThresholdKey) ?? 200;
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
    final result = await Navigator.push<PrinterSetup>(context,MaterialPageRoute(builder: (_) =>
      PrinterSetupPage(printer: printer,slicer: slicer,nozzle: nozzle,bed: bed)));
    if (result == null || !mounted || prefs == null) return;
    try {
      await savePrinterBed(prefs!,result.printer,result.bed);
      setState(() { printer = result.printer; slicer = result.slicer; nozzle = result.nozzle; bed = result.bed; configured = true; });
      await save();
    } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Einrichtung konnte nicht gespeichert werden.'))); }
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
    if (Platform.isWindows || Platform.isLinux) { await enterCode(); return; }
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

  Future<void> openModel() async {
    if (bed == null) await setup();
    if (!mounted || bed == null) return;
    await Navigator.push(context,MaterialPageRoute(builder: (_) => ModelPreviewPage(
      printer: printer,slicer: slicer,nozzle: nozzle,quality: qualityMode,bed: bed)));
  }
  Future<void> openBuildPlate() async {
    if (bed == null) await setup();
    if (!mounted || bed == null) return;
    await Navigator.push(context,MaterialPageRoute(builder: (_) => BuildPlatePage(pickPart: pickPlatePart,bed: bed!,printer: printer)));
  }
  void openLowStock() => Navigator.push(context,MaterialPageRoute(builder: (_) => LowStockPage(stock: stock,
    threshold: lowStockThreshold,onThresholdChanged: (value) { if (mounted) setState(() => lowStockThreshold = value); })));

  @override Widget build(BuildContext context) => PopScope(
    canPop: !inventoryOpen, onPopInvokedWithResult: (didPop, result) {
      if (!didPop && inventoryOpen) setState(() => inventoryOpen = false);
    }, child: Scaffold(
    appBar: AppBar(title: Text(inventoryOpen ? 'Filamentlager' : 'Print Optimizer'),
      leading: inventoryOpen ? IconButton(tooltip: 'Zur Startseite', icon: const Icon(Icons.arrow_back),
        onPressed: () => setState(() => inventoryOpen = false)) : null,
      actions: [
        IconButton(tooltip: 'Druckhilfe',onPressed: () => Navigator.push(context,MaterialPageRoute(builder: (_) => const HelpChatPage())),icon: const Icon(Icons.chat_bubble_outline)),
        IconButton(tooltip: 'Updates prüfen', onPressed: () => checkForUpdates(manual: true), icon: const Icon(Icons.system_update)),
        IconButton(tooltip: 'Einrichtung', onPressed: setup, icon: const Icon(Icons.settings_outlined)),
      ]),
    body: SafeArea(top: false, child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth:960),child: prefs == null ? const Center(child: CircularProgressIndicator()) :
      ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
        if (!inventoryOpen) ...[
          const SizedBox(height:8),
          StudioHero(onOpen:openModel),
          const StudioHeading('Deine Werkzeuge',subtitle:'Vorbereiten, organisieren, loslegen.'),
          StudioTools(children:[
            StudioTool(title:'Druckplatte',subtitle:'Mehrere Teile zusammenstellen',icon:Icons.dashboard_customize_outlined,
              color:const Color(0xffda6b37),onTap:openBuildPlate),
            StudioTool(title:'Druckprojekte',subtitle:'Gespeicherte Einstellungen',icon:Icons.folder_copy_outlined,
              color:studioPurple,onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const PrintProjectsPage()))),
            StudioTool(title:'Meine Düsen',subtitle:'Dein Bestand, passend zum Druck',icon:Icons.settings_input_component_outlined,
              color:const Color(0xff3776be),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>NozzleInventoryPage(printer:printer,installed:nozzle)))),
            StudioTool(title:'Filamentlager',subtitle:'${stock.length} Rollen · ${reorderFilaments(stock,lowStockThreshold).length} nachbestellen',
              icon:Icons.cyclone_outlined,color:const Color(0xff18867a),onTap:()=>setState(()=>inventoryOpen=true)),
          ]),
          const StudioHeading('Dein Drucker'),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [const Icon(Icons.print_outlined, size: 20), const SizedBox(width: 10),
                Expanded(child: Text(printer, style: const TextStyle(fontWeight: FontWeight.w600))),
                Text('$nozzle mm', style: TextStyle(color: Theme.of(context).colorScheme.primary))]),
              const SizedBox(height: 8), Text(slicer, style: const TextStyle(color: studioMuted)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(isExpanded: true,initialValue: qualityMode,
                decoration: const InputDecoration(labelText: 'Standard-Druckmodus'),
                items: ['Maximale Qualität', 'Ausgewogen', 'Schneller Druck']
                  .map((mode) => DropdownMenuItem(value: mode, child: Text(mode))).toList(),
                onChanged: (value) async {
                  if (value == null) return;
                  setState(() => qualityMode = value); await save();
                }),
              if (!configured) TextButton.icon(onPressed: setup, icon: const Icon(Icons.settings_outlined),
                label: const Text('Drucker einrichten')),
            ]))),
        ] else ...[
          const Text('Dein Material.\nAlles im Blick.', style: TextStyle(fontSize: 30, height:1.15,letterSpacing:-.7,fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: scanFilament, icon: const Icon(Icons.qr_code_scanner), label: const Text('Barcode scannen')),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(onPressed: enterCode, icon: const Icon(Icons.keyboard), label: const Text('Filamentcode eingeben')),
            OutlinedButton.icon(onPressed: () => addFilament(), icon: const Icon(Icons.add), label: const Text('Manuell hinzufügen')),
          ]),
          const SizedBox(height: 18),
          Card(child: ListTile(leading: const Icon(Icons.shopping_cart_outlined),title: Text('Nachbestellen: ${reorderFilaments(stock,lowStockThreshold).length} Filamente'),
            subtitle: Text('Grenze: ${lowStockThreshold.toStringAsFixed(0)} g · gleiche Filamente zusammengezählt'),onTap: openLowStock,trailing: const Icon(Icons.chevron_right))),
          for (var i = 0; i < stock.length; i++) Card(child: ListTile(
            contentPadding: const EdgeInsets.all(14),
            leading: CircleAvatar(backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: const Icon(Icons.cyclone)),
            title: Text('${stock[i]['brand']} ${stock[i]['material']} ${stock[i]['color']}'),
            subtitle: Text('${stock[i]['grams']} g${(stockGrams(stock[i]['grams']) ?? double.infinity) <= lowStockThreshold ? ' · Fast leer' : ''} · ${stock[i]['barcode']}'),
            onTap: () => addFilament(index: i),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(tooltip: 'Restmenge bearbeiten', icon: const Icon(Icons.edit_outlined), onPressed: () => addFilament(index: i)),
              IconButton(tooltip: 'Rolle löschen', icon: const Icon(Icons.delete_outline), onPressed: () async {
                final next = [...stock]..removeAt(i);
                if (await prefs!.setString('stock', jsonEncode(next)) && mounted) setState(() => stock = next);
              }),
            ]))),
          if (stock.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Column(children: [
            Icon(Icons.cyclone, size: 56, color: Color(0xff6ee7d8)), SizedBox(height: 16),
            Text('Dein Lager ist noch leer.', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            Text('Scanne deine erste Rolle oder füge sie manuell hinzu.'),
          ])),
        ],
      ])))),
  ));
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
  late Float32List sourceVertices = _normalizedVertices();
  Float32List? posedVertices;
  int printAxis = 0;
  _V3? poseSize;
  Float32List get renderVertices => posedVertices ?? sourceVertices;
  double get radius => math.max(.001, math.sqrt(sourceSize.x*sourceSize.x+sourceSize.y*sourceSize.y+sourceSize.z*sourceSize.z)/2);
  _Mesh oriented(Float32List pose, SupportAssessment assessment, int axis, (double,double,double) extent) {
    final copy = _Mesh(faces,minimum,maximum,totalFaces);
    copy.sourceVertices = sourceVertices;
    copy.posedVertices = pose; copy.printAxis = axis; copy.supports = assessment;
    copy.poseSize = _V3(extent.$1*radius,extent.$2*radius,extent.$3*radius);
    return copy;
  }

  Float32List _normalizedVertices() {
    final center = _V3(minimum.x / 2 + maximum.x / 2,
        minimum.y / 2 + maximum.y / 2, minimum.z / 2 + maximum.z / 2);
    final extent = sourceSize;
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

  _V3 get sourceSize => _V3(maximum.x-minimum.x, maximum.y-minimum.y, maximum.z-minimum.z);
  _V3 get size => poseSize ?? sourceSize;
}

class _MeshReader {
  static PlatePart plateInBackground((String,Uint8List) input) {
    final mesh = fromBytes(input.$1,input.$2);
    return PlatePart(name: input.$1,vertices: mesh.sourceVertices,unitScale: mesh.radius,
      width: mesh.size.x,depth: mesh.size.y,height: mesh.size.z);
  }
  static _Mesh inBackground((String, Uint8List) input) {
    final parsed = fromBytes(input.$1, input.$2);
    // Prepare the render buffer on the worker too, before returning to the UI.
    parsed.supports = assessSupports(parsed.renderVertices);
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
    final vertices = readThreeMfTriangles(bytes);
    final faces = <_Triangle>[];
    for (var i = 0; i < vertices.length; i += 9) {
      _V3 point(int offset) => _V3(vertices[offset],vertices[offset+1],vertices[offset+2]);
      faces.add(_Triangle(point(i),point(i+3),point(i+6)));
    }
    return _summarize(faces);
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
    this.slicer = 'Anycubic Slicer Next', this.nozzle = '0.4', this.quality = 'Maximale Qualität',this.bed});
  final String printer, slicer, nozzle, quality;
  final PrinterBed? bed;
  @override State<ModelPreviewPage> createState() => _ModelPreviewPageState();
}

class _ModelPreviewPageState extends State<ModelPreviewPage> {
  _Mesh? mesh;
  PrinterBed? get printerBed => widget.bed ?? knownPrinterBed(widget.printer);
  String? fileName, error;
  String projectId = DateTime.now().microsecondsSinceEpoch.toString();
  bool loading = false;
  bool showOverhangs = true;
  double modelScale = 1;
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
      final input = await chooseModelBytes();
      if (input == null) return;
      final parsed = await compute(_MeshReader.inBackground,input);
      if (!mounted) return;
      setState(() { mesh = parsed; fileName = input.$1; projectId = DateTime.now().microsecondsSinceEpoch.toString(); modelScale = 1; angleX = 25; angleY = 30; zoom = 1; });
    } catch (e) {
      if (mounted) setState(() => error = 'Datei konnte nicht geöffnet werden: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> optimizeOrientation() async {
    final m = mesh;
    if (m == null || loading || !m.supports.valid) return;

    setState(() { loading = true; error = null; });
    try {
      // The candidate is relative to the current pose. Keep the original
      // source buffer shared and rotate only its compact preview buffer.
      final result = await compute(orientForPrinter,(m.renderVertices,m.supports,m.radius*modelScale,printerBed));
      if (!mounted) return;
      final copy = m.oriented(result.$1,result.$2,-1,result.$3);
      setState(() { mesh = copy; angleX = 25; angleY = 30; zoom = 1; });
    } catch (e) { if (mounted) setState(() => error = 'Drucklage: $e'); }
    finally { if (mounted) setState(() => loading = false); }
  }
  Future<void> restorePrintPose() async {
    final m = mesh;
    if (m == null || loading) return;
    setState(() => loading = true);
    try {
      final result = await compute(orientPrintModel,(m.sourceVertices,0));
      if (mounted) setState(() { mesh = m.oriented(result.$1,result.$2,0,result.$3); });
    } finally { if (mounted) setState(() => loading = false); }
  }
  Future<void> editSize(bool width) async {
    final m = mesh;
    if (m == null || loading) return;
    final scale = await showDialog<double>(context: context, builder: (_) =>
      ModelSizeDialog(scale: modelScale,width: m.size.x,editWidth: width));
    if (mounted && scale != null) setState(() => modelScale = scale);
  }
  Future<void> cutModel() async {
    final m = mesh;
    if (m == null || loading || printerBed == null) return;
    final parts = await requestModelCut(context,PlatePart(name: fileName ?? 'Modell',vertices: m.renderVertices,
      unitScale: m.radius,width: m.size.x,depth: m.size.y,height: m.size.z),modelScale,bed: printerBed);
    if (!mounted || parts == null) return;
    await Navigator.push(context,MaterialPageRoute(builder: (_) => BuildPlatePage(pickPart: pickPlatePart,bed: printerBed!,printer: widget.printer,initialParts: parts)));
  }
  Future<void> saveModel() async {
    final m = mesh;
    if (m == null || loading) return;
    setState(() { loading = true; error = null; });
    try {
      final bytes = await compute(encodePrintStl,(m.renderVertices,m.radius*modelScale));
      if (!mounted) return;
      final base = (fileName ?? 'Modell').replaceAll(RegExp(r'[^a-zA-Z0-9._-]'),'_');
      final target = await FilePicker.platform.saveFile(dialogTitle: 'Modell speichern',
        fileName: '${base}_angepasst.stl',type: FileType.custom,allowedExtensions: ['stl'],bytes: bytes);
      if (target == null) return;
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) await File(target).writeAsBytes(bytes,flush: true);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Neue STL-Datei mit Größe und Drucklage gespeichert.')));
    } catch (_) { if (mounted) setState(() => error = 'Modelldatei konnte nicht gespeichert werden.'); }
    finally { if (mounted) setState(() => loading = false); }
  }

  @override Widget build(BuildContext context) {
    final m = mesh;
    return Scaffold(
      appBar: AppBar(title: const Text('Modell'), actions: [
        TextButton(onPressed: m == null || loading ? null : saveModel, child: const Text('Datei speichern')),
        TextButton(onPressed: m == null || loading ? null : () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => ProjectOptimizerPage(project: PrintProject(
            id: projectId, fileName: fileName ?? 'Modell',
            dimensions: '${(m.size.x*modelScale).toStringAsFixed(2)} × ${(m.size.y*modelScale).toStringAsFixed(2)} × ${(m.size.z*modelScale).toStringAsFixed(2)} mm',
            bed: printerBed,modelScale: modelScale, orientation: m.printAxis == 0 ? 'Wie in der Datei' : 'Optimiert · angepasste STL verwenden',
            printer: widget.printer, slicer: widget.slicer, nozzle: widget.nozzle,
            priority: widget.quality, supportStatus: m.supports.status, supportReason: m.supports.reason)))), child: const Text('OK')),
      ]),
      body: SafeArea(top: false, child: ListView(padding: const EdgeInsets.all(16), children: [
        FilledButton.icon(onPressed: loading ? null : openModel,
          icon: const Icon(Icons.folder_open),
          label: Text(loading ? 'Datei wird geladen...' : 'STL / 3MF auswählen')),
        if (error != null) Padding(padding: const EdgeInsets.all(12),
          child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (m != null) ...[
          const SizedBox(height: 12),
          Text(fileName ?? 'Modell', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Container(height: math.max(280,math.min(440,MediaQuery.sizeOf(context).height*.42)), decoration: BoxDecoration(
            color: const Color(0xff1c1a2d),
            borderRadius: BorderRadius.circular(24)),
            child: ClipRRect(borderRadius: BorderRadius.circular(24),
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
                  return CustomPaint(painter: const StudioViewportPainter(),child: _SurfacePreview(mesh: m, angleX: angleX, angleY: angleY,
                    zoom: zoom, showOverhangs: showOverhangs, width: math.max(1, (constraints.maxWidth * factor).round()),
                    height: math.max(1, (constraints.maxHeight * factor).round())));
                }))))),
          const SizedBox(height: 8),
          const Row(children:[Icon(Icons.touch_app_outlined,size:16,color:studioMuted),SizedBox(width:6),Expanded(child:Text('Drehen · Zoomen',style:TextStyle(color:studioMuted,fontSize:13)))]),
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
          const StudioHeading('Größe & Bauraum'),
          Text('Größe: ${(modelScale*100).toStringAsFixed(1)} %'),
          if (printerBed != null &&
            (m.size.x*modelScale > printerBed!.width || m.size.y*modelScale > printerBed!.depth || m.size.z*modelScale > printerBed!.height))
            Text('Modell ist größer als der Bauraum von ${widget.printer}.', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          Text('Abmessungen: ${(m.size.x*modelScale).toStringAsFixed(2)} × ${(m.size.y*modelScale).toStringAsFixed(2)} × ${(m.size.z*modelScale).toStringAsFixed(2)} mm'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton(onPressed: loading ? null : () => editSize(false), child: const Text('Größe in %')),
            OutlinedButton(onPressed: loading || m.size.x <= 0 ? null : () => editSize(true), child: const Text('Breite in mm')),
            if (modelScale != 1) TextButton(onPressed: () => setState(() => modelScale = 1), child: const Text('Originalgröße')),
          ]),
          const Text('Proportionen bleiben erhalten. Oben als neue STL speichern.'),
          if (Platform.isAndroid) OutlinedButton.icon(onPressed: loading || printerBed == null ? null : cutModel,
            icon: const Icon(Icons.content_cut),label: const Text('Teilen & verbinden')),
          if (printerBed != null) Text('Bauraum: ${printerBed!.width} × ${printerBed!.depth} × ${printerBed!.height} mm'),
          OutlinedButton.icon(onPressed: loading || printerBed == null ? null : () => Navigator.push(context,MaterialPageRoute(builder: (_) =>
            BuildPlatePage(pickPart: pickPlatePart,bed: printerBed ?? const PrinterBed(250,250,250),printer: widget.printer,initialScale: modelScale,initialPart: PlatePart(name: fileName ?? 'Modell',
              vertices: m.renderVertices,unitScale: m.radius,width: m.size.x,depth: m.size.y,height: m.size.z)))),
            icon: const Icon(Icons.add),label: const Text('Weitere Datei auf Druckplatte hinzufügen')),
          const StudioHeading('Drucklage & Stützen'),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Überhänge rot anzeigen'),
            value: showOverhangs, onChanged: m.supports.valid ? (value) => setState(() => showOverhangs = value) : null),
          OutlinedButton(onPressed: () => setState(() { angleX = 180; angleY = 0; zoom = 1; }), child: const Text('Unterseite ansehen')),
          FilledButton.icon(onPressed: loading || !m.supports.valid ? null : optimizeOrientation,
            icon: const Icon(Icons.screen_rotation_alt), label: const Text('Automatisch ausrichten')),
          if (m.printAxis != 0) TextButton(onPressed: loading ? null : restorePrintPose, child: const Text('Original-Drucklage')),
          const Text('Vergleich von Drucklagen nach Überhangfläche, Auflagefläche und Bauraum. Kein Festigkeitsnachweis.'),

          Text('Dreiecke: ${m.totalFaces}'),
          Text('Stützen: ${m.supports.status}'),
          if (m.supports.valid) Text('Kritische Fläche: ${(m.supports.overhangFraction*100).toStringAsFixed(1)} % der Oberfläche'),
          Text(m.supports.reason),
          const Text('Drehen mit dem Finger ändert nur die Ansicht. Optimierte Drucklage und Größe oben als neue STL speichern. STL enthält keine 3MF-Farben.'),
          const SizedBox(height: 12),
          const Text('Originaldatei bleibt unverändert. Stützenhinweis im Slicer prüfen.'),
        ] else if (!loading) ...[
          const SizedBox(height: 32),
          const Icon(Icons.view_in_ar, size: 64),
          const SizedBox(height: 12),
          const Center(child: Text('Öffne eine STL- oder 3MF-Datei.')),
        ],
      ])),
    );
  }
}

class _SurfacePreview extends StatefulWidget {
  const _SurfacePreview({required this.mesh, required this.angleX,
    required this.angleY, required this.zoom, required this.showOverhangs, required this.width, required this.height});
  final _Mesh mesh;
  final double angleX, angleY, zoom;
  final bool showOverhangs;
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
        oldWidget.angleY != widget.angleY || oldWidget.zoom != widget.zoom || oldWidget.showOverhangs != widget.showOverhangs ||
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
            widget.width, widget.height, widget.angleX, widget.angleY, widget.zoom,
            overhangFaces: widget.showOverhangs ? mesh.supports.overhangFaces : null);
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
      if (_error != null) Center(child: Text(_error!,style:const TextStyle(color:Colors.white70))),
    ]));
}
