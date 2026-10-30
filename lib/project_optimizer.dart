import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'material_advice.dart';
import 'slicer_export.dart';
import 'printer_setup.dart';
import 'nozzles.dart';
import 'help_chat.dart';

const projectStorageKey = 'model_projects_v1';

class PrintProject {
  PrintProject({required this.id, required this.fileName, required this.dimensions,
    required this.printer, required this.slicer, required this.nozzle,
    this.functional = false, this.outdoor = false, this.highLoad = false,
    this.flexible = false, this.warm = false, this.surface = 'Sehr glatt',
    this.priority = 'Maximale Qualität', this.supportStatus = 'Im Slicer prüfen',
    this.supportReason = 'Keine Geometrieprüfung gespeichert.', this.modelScale = 1, this.orientation = 'Wie in der Datei',this.bed});
  final String id, fileName, dimensions, printer, slicer, nozzle;
  final bool functional, outdoor, highLoad, flexible, warm;
  final String surface, priority, supportStatus, supportReason, orientation;
  final double modelScale;
  final PrinterBed? bed;
  MaterialAdvice get advice => recommendMaterial(functional: functional,
    outdoor: outdoor, highLoad: highLoad, flexible: flexible, warm: warm,
    quality: surface == 'Sehr glatt' ? 'Maximale Qualität' : priority);
  Map<String, dynamic> toJson() => {
    'bed': bed?.toJson(), 'modelScale': modelScale, 'orientation': orientation, 'id': id, 'fileName': fileName, 'dimensions': dimensions, 'printer': printer,
    'slicer': slicer, 'nozzle': nozzle, 'functional': functional, 'outdoor': outdoor,
    'highLoad': highLoad, 'flexible': flexible, 'warm': warm,
    'surface': surface, 'priority': priority, 'supportStatus': supportStatus, 'supportReason': supportReason,
  };
  factory PrintProject.fromJson(Map<String, dynamic> data) => PrintProject(
    bed: data['bed'] is Map ? PrinterBed.fromJson(Map<String,dynamic>.from(data['bed'] as Map)) : knownPrinterBed(data['printer'] as String),
    modelScale: (data['modelScale'] as num?)?.toDouble() ?? 1,
    orientation: data['orientation'] as String? ?? 'Wie in der Datei', id: data['id'] as String, fileName: data['fileName'] as String,
    dimensions: data['dimensions'] as String, printer: data['printer'] as String,
    slicer: data['slicer'] as String, nozzle: data['nozzle'] as String,
    functional: data['functional'] == true, outdoor: data['outdoor'] == true,
    highLoad: data['highLoad'] == true, flexible: data['flexible'] == true,
    warm: data['warm'] == true, surface: data['surface'] as String,
    priority: data['priority'] as String, supportStatus: data['supportStatus'] as String? ?? 'Im Slicer prüfen',
    supportReason: data['supportReason'] as String? ?? 'Keine Geometrieprüfung gespeichert.');
}

Future<List<PrintProject>> loadPrintProjects() async {
  final prefs = await SharedPreferences.getInstance();
  final rows = jsonDecode(prefs.getString(projectStorageKey) ?? '[]') as List;
  return rows.map((row) => PrintProject.fromJson(Map<String, dynamic>.from(row as Map))).toList();
}

Future<void> savePrintProject(PrintProject project) async {
  final projects = await loadPrintProjects();
  final index = projects.indexWhere((p) => p.id == project.id);
  if (index < 0) { projects.insert(0, project); } else { projects[index] = project; }
  final prefs = await SharedPreferences.getInstance();
  if (!await prefs.setString(projectStorageKey,
      jsonEncode(projects.map((p) => p.toJson()).toList()))) {
    throw StateError('Projekt konnte nicht gespeichert werden.');
  }
}

class ProjectOptimizerPage extends StatefulWidget {
  const ProjectOptimizerPage({super.key, required this.project, this.showResult = false});
  final PrintProject project;
  final bool showResult;
  @override State<ProjectOptimizerPage> createState() => _ProjectOptimizerPageState();
}

class _ProjectOptimizerPageState extends State<ProjectOptimizerPage> {
  late bool functional, outdoor, highLoad, flexible, warm, result;
  late String surface, priority;
  bool saving = false;
  String? error;
  List<OwnedNozzle> ownedNozzles = [];
  late String selectedNozzle = widget.project.nozzle.replaceAll(',','.');
  String? installedNozzle;
  Future<void> loadOwnedNozzles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rows = await loadNozzles(seedPrinter: prefs.getString('printer') ?? widget.project.printer,seedDiameter: prefs.getString('nozzle') ?? widget.project.nozzle);
      if (mounted) setState(() { ownedNozzles = rows; installedNozzle = prefs.getString('nozzle') ?? widget.project.nozzle; });
    } catch (_) { /* Recommendations keep working with the configured nozzle. */ }
  }
  @override void initState() {
    super.initState();
    final p = widget.project;
    functional = p.functional; outdoor = p.outdoor; highLoad = p.highLoad;
    flexible = p.flexible; warm = p.warm; surface = p.surface; priority = p.priority;
    result = widget.showResult;
    loadOwnedNozzles();
  }
  PrintProject get current => PrintProject(id: widget.project.id,
    fileName: widget.project.fileName, dimensions: widget.project.dimensions,
    printer: widget.project.printer, slicer: widget.project.slicer,
    bed: widget.project.bed, modelScale: widget.project.modelScale, orientation: widget.project.orientation,
    nozzle: selectedNozzle, supportStatus: widget.project.supportStatus,
    supportReason: widget.project.supportReason, functional: functional, outdoor: outdoor,
    highLoad: highLoad, flexible: flexible, warm: warm, surface: surface, priority: priority);
  Future<void> finish() async {
    setState(() { saving = true; error = null; });
    try {
      await savePrintProject(current);
      if (mounted) setState(() => result = true);
    } catch (_) {
      if (mounted) setState(() => error = 'Speichern fehlgeschlagen. Deine Antworten bleiben hier erhalten. Bitte erneut versuchen.');
    } finally { if (mounted) setState(() => saving = false); }
  }
  Future<void> exportSettings(String action) async {
    final asFile = action != 'copy';
    try {
      final text = projectSettingsText(current);
      final profiles = action == 'slicer';
      if (asFile) {
        final bytes = profiles ? createSlicerPresetZip(current) : Uint8List.fromList(utf8.encode(text));
        final name = widget.project.fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        final target = await FilePicker.platform.saveFile(dialogTitle: 'Druckeinstellungen speichern',
          fileName: profiles ? '${name}_Slicerprofile.zip' : '${name}_Einstellungen.txt', type: FileType.custom,
          allowedExtensions: [profiles ? 'zip' : 'txt'], bytes: bytes);
        if (target == null) return;
        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
          await File(target).writeAsBytes(bytes, flush: true);
        }
      } else { await Clipboard.setData(ClipboardData(text: text)); }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(action == 'slicer' ? 'ZIP im Slicer über den Konfigurationsimport laden; danach die beiden Print-Optimizer-Profile wählen.' : asFile ? 'Einstellungsdatei gespeichert.' : 'Einstellungen kopiert.')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Export fehlgeschlagen. Bitte erneut versuchen.')));
    }
  }
  @override Widget build(BuildContext context) {
    final p = current;
    final available = <String>{selectedNozzle,for (final n in ownedNozzles)
      if (n.printer.trim().toLowerCase() == p.printer.trim().toLowerCase() && n.quantity > 0) n.diameter.toString()}.toList();
    final proposal = recommendOwnedNozzle(ownedNozzles,p.printer,fine: surface == 'Sehr glatt',
      fast: priority == 'Schneller Druck',functional: functional || highLoad);
    return Scaffold(appBar: AppBar(title: Text(result ? 'Deine Druckempfehlung' : 'Was ist dir wichtig?'),
      actions: [IconButton(tooltip: 'Druckhilfe',icon: const Icon(Icons.chat_bubble_outline),
        onPressed: () => Navigator.push(context,MaterialPageRoute(builder: (_) => HelpChatPage(project: current)))),
        if (!result) TextButton(onPressed: saving ? null : finish,
        child: Text(saving ? 'Speichert …' : 'Speichern')),
        if (result) PopupMenuButton<String>(tooltip: 'Einstellungen exportieren',
          onSelected: exportSettings, itemBuilder: (_) => [
            const PopupMenuItem(value: 'copy', child: Text('Einstellungen kopieren')),
            const PopupMenuItem(value: 'text', child: Text('Als Textdatei speichern')),
            if (supportsSlicerPresetExport(current)) const PopupMenuItem(value: 'slicer', child: Text('Slicerprofile speichern (ZIP)'),),
          ]),
      ]),
      body: SafeArea(top: false, child: ListView(padding: const EdgeInsets.all(16), children: [
        Text(p.fileName, style: Theme.of(context).textTheme.titleLarge),
        Text(p.dimensions),
        const SizedBox(height: 16),
        if (result) ...[
          if (proposal != null && proposal.diameter != double.tryParse(selectedNozzle)) Card(child: Padding(
            padding: const EdgeInsets.all(16),child: Column(crossAxisAlignment: CrossAxisAlignment.start,children: [
              Text('Vorhandene Alternative: ${proposal.diameter} mm · ${proposal.material}'),
              Text(surface == 'Sehr glatt' ? 'Kleinere Düse für Details; längere Druckzeit.' : 'Größere Düse für gröbere, schnellere Drucke.'),
              TextButton(onPressed: saving ? null : () async { setState(() => selectedNozzle = proposal.diameter.toString()); await finish(); },
                child: Text('Mit ${proposal.diameter} mm berechnen')),
            ]))),
          if (installedNozzle != null && double.tryParse(selectedNozzle) != double.tryParse(installedNozzle!.replaceAll(',','.')))
            const Text('Düse vor dem Drucken am Gerät wechseln und im Slicer passend auswählen.'),
          ProjectRecommendation(project: p),
          OutlinedButton(onPressed: () => setState(() => result = false),
            child: const Text('Antworten ändern')),
          const Text('Gespeichert in „Meine Druckprojekte“. Originaldatei bleibt unverändert.'),
        ] else ...[
          const Text('Beantworte die Fragen für dieses Modell und tippe oben auf Speichern. Danach erhältst du Material und Druckeinstellungen zusammen.'),
          SwitchListTile(title: const Text('Mechanisches Teil / Gebrauchsteil'), value: functional,
            onChanged: saving ? null : (v) => setState(() => functional = v)),
          SwitchListTile(title: const Text('Dauerhaft draußen / in der Sonne'), value: outdoor,
            onChanged: saving ? null : (v) => setState(() => outdoor = v)),
          SwitchListTile(title: const Text('Hohe mechanische Belastung'), value: highLoad,
            onChanged: saving ? null : (v) => setState(() => highLoad = v)),
          SwitchListTile(title: const Text('Muss weich oder biegsam sein'), value: flexible,
            onChanged: saving ? null : (v) => setState(() => flexible = v)),
          SwitchListTile(title: const Text('Erhöhte Wärme, z. B. im Auto'), value: warm,
            onChanged: saving ? null : (v) => setState(() => warm = v)),
          DropdownButtonFormField<String>(initialValue: selectedNozzle,decoration: const InputDecoration(labelText: 'Düse für diese Empfehlung'),
            items: available.map((d) => DropdownMenuItem(value: d,child: Text('$d mm'))).toList(),
            onChanged: saving ? null : (v) => setState(() => selectedNozzle = v ?? selectedNozzle)),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(initialValue: surface,
            decoration: const InputDecoration(labelText: 'Wie soll die Oberfläche sein?'),
            items: ['Sehr glatt', 'Standard', 'Funktion wichtiger als Optik']
              .map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: saving ? null : (v) => setState(() => surface = v!)),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(initialValue: priority,
            decoration: const InputDecoration(labelText: 'Was hat Vorrang?'),
            items: ['Maximale Qualität', 'Ausgewogen', 'Schneller Druck']
              .map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: saving ? null : (v) => setState(() => priority = v!)),
          const SizedBox(height: 16),
          if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const Text('Fertig? Tippe oben auf Speichern, um deine Empfehlung zu sehen.'),
        ],
      ])));
  }
}

// General starting points within the published material ranges, not a brand profile.
// https://help.prusa3d.com/filament-material-guide
// https://de.store.sunlu.com/blogs/3d-printing-guide/der-ultimative-leitfaden-zu-3d-drucker-filamenten-pla-abs-petg-mehr-2025
({int nozzle, int bed})? materialTemperatures(String material) => switch (material) {
  'PLA' => (nozzle: 205, bed: 55),
  'PETG' => (nozzle: 240, bed: 80),
  'ASA' => (nozzle: 250, bed: 100),
  'TPU' => (nozzle: 220, bed: 50),
  _ => null,
};

({int outer,int inner,int infill,int top,int bridge,int first,double flowLimit}) printSpeeds(PrintProject p) {
  final material = p.advice.material;
  final fine = p.surface == 'Sehr glatt' || p.priority == 'Maximale Qualität';
  final balanced = p.priority == 'Ausgewogen';
  return material == 'TPU' ? (outer: 25,inner: 25,infill: 25,top: 20,bridge: 20,first: 20,flowLimit: 2.5)
    : (outer: fine ? 35 : balanced ? 50 : 80, inner: fine ? 60 : balanced ? 80 : 100,
       infill: fine ? 80 : balanced ? 100 : 120, top: fine ? 30 : balanced ? 40 : 50,
       bridge: 25,first: 20,flowLimit: material == 'PETG' ? 6.0 : 8.0);
}

({double layer,double first,double line,int top,int bottom}) projectNozzleGeometry(PrintProject p) =>
  nozzleGeometry(double.tryParse(p.nozzle.replaceAll(',','.')) ?? .4,
    p.surface == 'Sehr glatt' ? 'Maximale Qualität' : p.priority);

Map<String, String> projectSettings(PrintProject p) {
  final a = p.advice;
  final t = materialTemperatures(a.material);
  final diameter = double.tryParse(p.nozzle.replaceAll(',','.'));
  final standardNozzle = diameter != null && diameter >= .1 && diameter <= 2;
  final geometry = projectNozzleGeometry(p);
  final speeds = printSpeeds(p);
  return {
    'Filament': a.material,
    if (t != null) 'Filament-Temperatur': '${t.nozzle} °C',
    if (t != null) 'Druckbett': '${t.bed} °C',
    'Düse': '${p.nozzle} mm',
    if (p.bed != null) 'Bauraum': '${p.bed!.width} × ${p.bed!.depth} × ${p.bed!.height} mm',
    if (standardNozzle) 'Schichthöhe': '${geometry.layer.toStringAsFixed(3).replaceAll('.',',')} mm',
    if (standardNozzle) 'Erste Schicht': '${geometry.first} mm · ${speeds.first} mm/s',
    if (standardNozzle) 'Linienbreite': '${geometry.line} mm',
    if (standardNozzle) 'Wände': '${a.walls}',
    if (standardNozzle) 'Füllung': '${a.infill} % · Gyroid',
    if (standardNozzle) 'Deck-/Bodenschichten': '${geometry.top} / ${geometry.bottom}',
    if (standardNozzle) 'Außenwand': '${speeds.outer} mm/s',
    if (standardNozzle) 'Innenwände': '${speeds.inner} mm/s',
    if (standardNozzle) 'Füllgeschwindigkeit': '${speeds.infill} mm/s',
    if (standardNozzle) 'Deckflächen': '${speeds.top} mm/s',
    if (standardNozzle) 'Brücken': '${speeds.bridge} mm/s',
    'Max. Volumenstrom': '${speeds.flowLimit} mm³/s',
    'Kühlung': a.material == 'PLA' ? '100 % ab Schicht 3'
      : a.material == 'PETG' ? '50 % ab Schicht 3'
      : a.material == 'ASA' ? '0 % (Brücken: Materialprofil)' : 'TPU-Herstellerprofil',
    'Rückzug': 'Drucker-/Filamentprofil',
    'Fluss / Beschleunigung': 'Kalibriertes Druckerprofil',
    'Haftung': a.material == 'ASA' ? '8 mm Brim · geeignetes Haftmittel'
      : a.material == 'TPU' ? 'Trennschicht nach Druckplattenfreigabe'
      : a.material == 'PETG' ? 'Trennschicht auf glatter PEI-Platte' : 'Saubere Druckplatte',
    'Bauraumtemperatur': a.material == 'ASA' ? 'Geschlossen · geeignete Abluft' : 'Nicht aktiv beheizen',
    'Stützen': p.supportStatus,
    'Druckausrichtung': p.orientation,
    'Modellgröße': '${(p.modelScale*100).toStringAsFixed(1)} %',
    'Modelldatei': p.modelScale != 1 || p.orientation != 'Wie in der Datei' ? 'Angepasste STL verwenden' : 'Originaldatei',
    'Oberfläche': p.surface,
  };
}

String projectSettingsText(PrintProject project) => [
  '3D Print Optimizer · ${project.fileName}',
  '${project.printer} · ${project.slicer}',
  for (final row in projectSettings(project).entries) '${row.key}: ${row.value}',
  'Startwerte. Rollenetikett und kalibriertes Druckerprofil gehen vor.',
  'Stützenhinweis für die gewählte Drucklage; im Slicer prüfen.',
  'Textliste zur manuellen Übernahme. Importierbare Profile separat als ZIP exportieren.',
].join('\n');

class ProjectRecommendation extends StatelessWidget {
  const ProjectRecommendation({super.key, required this.project});
  final PrintProject project;
  @override Widget build(BuildContext context) {
    final p = project;
    final a = p.advice;
    final rows = projectSettings(p);
    final diameter = double.tryParse(p.nozzle.replaceAll(',','.'));
  final standardNozzle = diameter != null && diameter >= .1 && diameter <= 2;
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(Icons.tune, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10), Text('Deine Einstellungen', style: Theme.of(context).textTheme.titleLarge)]),
        const SizedBox(height: 12),
        for (final row in rows.entries) Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Text('${row.key}: ${row.value}', style: const TextStyle(fontSize: 16))),
        if (!standardNozzle) const Text('Weitere Werte: passendes Düsenprofil verwenden.'),
        const Divider(height: 24),
        const Text('Startwerte · Angaben auf deiner Filamentrolle gehen vor.', style: TextStyle(fontSize: 13)),
        ExpansionTile(tilePadding: EdgeInsets.zero, title: const Text('Hinweise und Begründung'), children: [
          Text(a.reason), const SizedBox(height: 12), Text(a.notes),
          const SizedBox(height: 12), Text(p.supportReason),
          const SizedBox(height: 12),
          Text('${p.printer} · ${p.slicer} · Priorität: ${p.priority}'),
          if (p.surface == 'Sehr glatt' && p.priority != 'Maximale Qualität')
            const Text('Sehr glatte Oberfläche hat Vorrang vor Geschwindigkeit.'),
          const SizedBox(height: 12),
          const Text('Überhangprüfung in gewählter Drucklage; Drehen mit dem Finger verändert nur die Ansicht. '
            'Brücken und Stützbereiche im Slicer prüfen. Kein Festigkeitsnachweis. '
            'Im Slicer ZIP-Profile importieren und auswählen. Bei geänderter Größe/Drucklage die angepasste STL verwenden. '),
          const SizedBox(height: 12),
        ]),
      ])));
  }
}

class PrintProjectsPage extends StatefulWidget {
  const PrintProjectsPage({super.key});
  @override State<PrintProjectsPage> createState() => _PrintProjectsPageState();
}
class _PrintProjectsPageState extends State<PrintProjectsPage> {
  late Future<List<PrintProject>> projects;
  @override void initState() { super.initState(); projects = loadPrintProjects(); }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Meine Druckprojekte')),
    body: FutureBuilder<List<PrintProject>>(future: projects, builder: (context, snapshot) {
      if (snapshot.hasError) return Center(child: TextButton(
        onPressed: () => setState(() => projects = loadPrintProjects()),
        child: const Text('Projekte konnten nicht geladen werden. Erneut versuchen')));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      if (snapshot.data!.isEmpty) return const Center(child: Text('Noch keine Projekte. Öffne zuerst eine STL- oder 3MF-Datei.'));
      return ListView(children: [for (final p in snapshot.data!) ListTile(
        title: Text(p.fileName), subtitle: Text('${p.advice.material} · ${p.surface}'),
        trailing: const Icon(Icons.chevron_right), onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => ProjectOptimizerPage(project: p, showResult: true)));
          if (mounted) setState(() => projects = loadPrintProjects());
        })]);
    }));
}
