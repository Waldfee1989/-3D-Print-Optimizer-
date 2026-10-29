import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Material properties: https://help.prusa3d.com/filament-material-guide
// ASA conditions: https://help.prusa3d.com/article/asa_1809
// Walls/infill below are conservative starting suggestions, not strength calculations.
class MaterialAdvice {
  MaterialAdvice({required this.material, required this.reason, required this.notes,
    required this.walls, required this.infill, required this.layer});
  final String material, reason, notes, layer;
  final int walls, infill;
}

MaterialAdvice recommendMaterial({required bool functional, required bool outdoor,
    required bool highLoad, required bool flexible, required bool warm, required String quality}) {
  final material = flexible ? 'TPU' : outdoor || warm ? 'ASA' : functional || highLoad ? 'PETG' : 'PLA';
  final reason = switch (material) {
    'TPU' => 'Für biegsame Teile, Puffer und weiche Auflagen ist flexibles Filament sinnvoll.',
    'ASA' => 'ASA kommt für Sonne, Witterung oder erhöhte Wärme eher infrage als PLA.',
    'PETG' => 'Für starre Alltagsteile ist PETG eine zähe Materialoption.',
    _ => 'PLA eignet sich gut für detailreiche Dekoration in Innenräumen ohne Wärmebelastung.',
  };
  final notes = <String>[
    if (material == 'ASA') 'Geschlossenen Bauraum und geeignete Abluft vorsehen; ASA kann sich verziehen.',
    if (material == 'TPU') 'Härtegrad, Förderweg und TPU-Profil prüfen; langsam drucken.',
    if (flexible && (outdoor || warm)) 'Für Wärme oder dauerhafte Sonne die Freigabe des konkreten TPU prüfen.',
    if (highLoad) 'Belastbarkeit hängt auch von Geometrie, Schichtausrichtung und Druckqualität ab. Bauteil praktisch prüfen.',
    'Temperaturen und Kühlung aus dem Profil für die konkrete Filamentrolle übernehmen.',
  ].join('\n\n');
  return MaterialAdvice(material: material, reason: reason, notes: notes,
    walls: highLoad ? 5 : functional ? 4 : 3, infill: highLoad ? 35 : functional ? 25 : 15,
    layer: quality == 'Maximale Qualität' ? '0,12 mm' : quality == 'Ausgewogen' ? '0,16 mm' : '0,20 mm');
}

class MaterialAdvicePage extends StatefulWidget {
  const MaterialAdvicePage({super.key, required this.quality, required this.nozzle});
  final String quality, nozzle;
  @override State<MaterialAdvicePage> createState() => _MaterialAdvicePageState();
}

class _MaterialAdvicePageState extends State<MaterialAdvicePage> {
  bool functional = false, outdoor = false, highLoad = false, flexible = false, warm = false;
  bool loading = true, saving = false;
  static const keyName = 'material_advice_v1';
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = jsonDecode(prefs.getString(keyName) ?? '{}') as Map;
      if (!mounted) return;
      setState(() {
        functional = data['functional'] == true; outdoor = data['outdoor'] == true;
        highLoad = data['highLoad'] == true; flexible = data['flexible'] == true; warm = data['warm'] == true;
      });
    } catch (_) { /* Bad saved answers fall back to indoor decoration. */ }
    finally { if (mounted) setState(() => loading = false); }
  }
  Future<void> saveAnswers() async {
    setState(() => saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(keyName, jsonEncode({
        'functional': functional, 'outdoor': outdoor, 'highLoad': highLoad,
        'flexible': flexible, 'warm': warm,
      }))) throw const FormatException('Speichern fehlgeschlagen.');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Antworten gespeichert.')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Antworten konnten nicht gespeichert werden.')));
    } finally { if (mounted) setState(() => saving = false); }
  }
  @override Widget build(BuildContext context) {
    final advice = recommendMaterial(functional: functional, outdoor: outdoor,
      highLoad: highLoad, flexible: flexible, warm: warm, quality: widget.quality);
    final standardNozzle = double.tryParse(widget.nozzle.replaceAll(',', '.')) == 0.4;
    return Scaffold(appBar: AppBar(title: const Text('Materialempfehlung')),
      body: loading ? const Center(child: CircularProgressIndicator()) : ListView(
        padding: const EdgeInsets.all(16), children: [
          const Text('Wofür verwendest du das Teil? Die Empfehlung folgt deinen Angaben; '
              'sie analysiert noch keine STL-/3MF-Geometrie.'),
          SwitchListTile(title: const Text('Gebrauchsteil statt Dekoration'), value: functional,
            onChanged: (v) => setState(() => functional = v)),
          SwitchListTile(title: const Text('Dauerhaft draußen / in der Sonne'), value: outdoor,
            onChanged: (v) => setState(() => outdoor = v)),
          SwitchListTile(title: const Text('Hohe mechanische Belastung'), value: highLoad,
            onChanged: (v) => setState(() => highLoad = v)),
          SwitchListTile(title: const Text('Muss weich oder biegsam sein'), value: flexible,
            onChanged: (v) => setState(() => flexible = v)),
          SwitchListTile(title: const Text('Erhöhte Wärme, z. B. im Auto'), value: warm,
            onChanged: (v) => setState(() => warm = v)),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Materialvorschlag: ${advice.material}', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8), Text(advice.reason),
              const SizedBox(height: 12), Text(advice.notes),
              const SizedBox(height: 12),
              if (standardNozzle) ...[
                Text('Startwerte für 0,4-mm-Düse · ${widget.quality}'),
                Text('Schichthöhe: ${advice.layer} · Wände: ${advice.walls} · Infill: ${advice.infill} %'),
              ] else const Text('Für diese Düsengröße das passende Slicer-Profil wählen; '
                  'die Startwerte dieser Empfehlung sind für 0,4 mm ausgelegt.'),
              const SizedBox(height: 8),
              const Text('Kein Festigkeitsnachweis. Einstellungen im Slicer prüfen; '
                  'das bisherige Druckprofil wird nicht automatisch verändert.'),
            ]))),
          FilledButton(onPressed: saving ? null : saveAnswers,
            child: Text(saving ? 'Wird gespeichert …' : 'Antworten merken')),
        ]));
  }
}
