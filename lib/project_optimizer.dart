import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'material_advice.dart';

const projectStorageKey = 'model_projects_v1';

class PrintProject {
  PrintProject({required this.id, required this.fileName, required this.dimensions,
    required this.printer, required this.slicer, required this.nozzle,
    this.functional = false, this.outdoor = false, this.highLoad = false,
    this.flexible = false, this.warm = false, this.surface = 'Sehr glatt',
    this.priority = 'Maximale Qualität', this.supportStatus = 'Im Slicer prüfen',
    this.supportReason = 'Keine Geometrieprüfung gespeichert.'});
  final String id, fileName, dimensions, printer, slicer, nozzle;
  final bool functional, outdoor, highLoad, flexible, warm;
  final String surface, priority, supportStatus, supportReason;
  MaterialAdvice get advice => recommendMaterial(functional: functional,
    outdoor: outdoor, highLoad: highLoad, flexible: flexible, warm: warm,
    quality: surface == 'Sehr glatt' ? 'Maximale Qualität' : priority);
  Map<String, dynamic> toJson() => {
    'id': id, 'fileName': fileName, 'dimensions': dimensions, 'printer': printer,
    'slicer': slicer, 'nozzle': nozzle, 'functional': functional, 'outdoor': outdoor,
    'highLoad': highLoad, 'flexible': flexible, 'warm': warm,
    'surface': surface, 'priority': priority, 'supportStatus': supportStatus, 'supportReason': supportReason,
  };
  factory PrintProject.fromJson(Map<String, dynamic> data) => PrintProject(
    id: data['id'] as String, fileName: data['fileName'] as String,
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
  @override void initState() {
    super.initState();
    final p = widget.project;
    functional = p.functional; outdoor = p.outdoor; highLoad = p.highLoad;
    flexible = p.flexible; warm = p.warm; surface = p.surface; priority = p.priority;
    result = widget.showResult;
  }
  PrintProject get current => PrintProject(id: widget.project.id,
    fileName: widget.project.fileName, dimensions: widget.project.dimensions,
    printer: widget.project.printer, slicer: widget.project.slicer,
    nozzle: widget.project.nozzle, supportStatus: widget.project.supportStatus,
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
  @override Widget build(BuildContext context) {
    final p = current;
    return Scaffold(appBar: AppBar(title: Text(result ? 'Deine Druckempfehlung' : 'Was ist dir wichtig?'),
      actions: [if (!result) TextButton(onPressed: saving ? null : finish,
        child: Text(saving ? 'Speichert …' : 'Speichern'))]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(p.fileName, style: Theme.of(context).textTheme.titleLarge),
        Text(p.dimensions),
        const SizedBox(height: 16),
        if (result) ...[
          ProjectRecommendation(project: p),
          OutlinedButton(onPressed: () => setState(() => result = false),
            child: const Text('Antworten ändern')),
          const Text('Projekt gespeichert. Unter „Meine Druckprojekte“ wieder öffnen. '
            'Gespeichert sind Dateiname, Abmessungen, Antworten und Einstellungen. '
            'Die Modelldatei bleibt an ihrem bisherigen Speicherort.'),
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
      ]));
  }
}

class ProjectRecommendation extends StatelessWidget {
  const ProjectRecommendation({super.key, required this.project});
  final PrintProject project;
  @override Widget build(BuildContext context) {
    final p = project;
    final a = p.advice;
    final standardNozzle = double.tryParse(p.nozzle.replaceAll(',', '.')) == .4;
    final speed = a.material == 'TPU' ? 'TPU-Profil der Filamentrolle verwenden; langsam drucken'
      : p.surface == 'Sehr glatt' || p.priority == 'Maximale Qualität' ? '35 mm/s'
      : p.priority == 'Ausgewogen' ? '50 mm/s' : '80 mm/s';
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Empfohlenes Material: ${a.material}', style: Theme.of(context).textTheme.titleLarge),
        Text(a.reason),
        const SizedBox(height: 12),
        Text('${p.printer} · ${p.slicer} · Düse ${p.nozzle} mm'),
        Text('Oberfläche: ${p.surface} · Priorität: ${p.priority}'),
        if (p.surface == 'Sehr glatt' && p.priority != 'Maximale Qualität')
          const Text('Für die sehr glatte Oberfläche haben feine Schichten Vorrang vor der Geschwindigkeit.'),
        const SizedBox(height: 12),
        if (standardNozzle) ...[
          Text('Schichthöhe: ${a.layer}'), Text('Wände: ${a.walls}'),
          Text('Infill: ${a.infill} %'), Text('Außenwand: $speed'),
        ] else const Text('Für diese Düsengröße ein passendes Slicer-Profil verwenden. Die Zahlenwerte sind für 0,4 mm ausgelegt.'),
        const Text('Temperatur, Druckbett, Kühlung und weitere Geschwindigkeiten: Profil für das empfohlene Material und die konkrete Filamentrolle verwenden.'),
        const SizedBox(height: 12),
        Text('Stützstrukturen: ${p.supportStatus}', style: Theme.of(context).textTheme.titleMedium),
        Text(p.supportReason),
        const Text('Gilt für die Ausrichtung der Datei. Vorschau-Drehung ändert die Druckausrichtung nicht. Bei anderer Ausrichtung im Slicer neu prüfen.'),
        const SizedBox(height: 12), Text(a.notes),
        const SizedBox(height: 12),
        const Text('Dies sind passende Startwerte aus deinen Antworten. Die Überhangprüfung ist eine geometrische Einschätzung; sie ersetzt keine Slicer-Vorschau. Belastbarkeit und vollständige Druckbarkeit werden nicht berechnet. '
          'Im Slicer prüfen und bei Bedarf mit einem Probedruck abstimmen. Keine automatische Übertragung in den Slicer.'),
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
