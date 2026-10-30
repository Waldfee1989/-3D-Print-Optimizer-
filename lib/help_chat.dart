import 'package:flutter/material.dart';
import 'project_optimizer.dart';

String answerPrintHelp(String question,PrintProject? project) {
  final q = question.toLowerCase().replaceAll('ä','ae').replaceAll('ö','oe').replaceAll('ü','ue').replaceAll('ß','ss');
  final settings = project == null ? null : projectSettings(project);
  if (q.contains('stuetz') || q.contains('ueberhang')) return '${settings == null ? '' : 'Aktuelles Projekt: ${settings['Stützen']}.\n\n'}Rote Flächen sind geometrisch kritische Überhänge. „Automatisch ausrichten“ vergleicht Drucklagen mit weniger Überhängen. Unterseiten und Brücken vor dem Drucken in der Slicer-Vorschau prüfen. „Im Slicer prüfen“ bedeutet, dass die Geometrie keine sichere Einschätzung erlaubt.';
  if (q.contains('temperatur') || q.contains('grad') || q.contains('bett')) return settings == null
    ? 'Nach Datei laden → Fragen beantworten → Speichern stehen Filament- und Druckbetttemperatur in der Einstellungsliste. Die Angaben auf deiner konkreten Filamentrolle gehen vor.'
    : '${settings['Filament']}: Düse ${settings['Filament-Temperatur']}, Druckbett ${settings['Druckbett']}. Das sind Startwerte. Wenn auf der Rolle andere Werte stehen, diese verwenden und bei Bedarf mit einem Temperaturtest abstimmen.';
  if (q.contains('infill') || q.contains('fuellung') || q.contains('stabil')) return 'Füllung ist die Struktur im Inneren des Teils. Mehr Füllung erhöht Materialbedarf und Druckzeit. Für Belastbarkeit sind auch Wände, Material und Schichtrichtung wichtig.${settings == null ? '' : '\nDein Projekt: ${settings['Füllung']}, ${settings['Wände']} Wände.'}';
  if (q.contains('duese') || q.contains('schicht') || q.contains('oberflaeche')) return 'Kleinere Düsen und feinere Schichten helfen bei Details, brauchen aber mehr Zeit. Unter „Meine Düsen“ trägst du deinen Bestand ein. Ein Düsenwechsel muss am Drucker und im Slicer tatsächlich übernommen werden. Die Empfehlung verändert die eingebaute Düse nicht automatisch.';
  if (q.contains('import') || q.contains('slicer') || q.contains('profil')) return 'In der Empfehlung oben im Menü „Slicerprofile speichern (ZIP)“ wählen. Am PC die ZIP über den Konfigurationsimport von Anycubic Slicer Next laden und beide Print-Optimizer-Profile auswählen. Der Import ist für Kobra S1 mit 0,4-mm-Düse eingerichtet. Für andere Kombinationen die Textliste und das passende Slicer-Profil verwenden.';
  if (q.contains('groess') || q.contains('kleiner') || q.contains('skalier')) return 'In der Modellansicht „Größe in %“ oder „Breite in mm“ wählen. Die Proportionen bleiben erhalten. Oben „Datei speichern“ legt eine neue STL mit dieser Größe an. Finger-Zoom verändert dagegen nur die Ansicht.';
  if (q.contains('platte') || q.contains('verschieb') || q.contains('mehrere')) return 'Unter „Mehrere Teile auf einer Platte“ fügst du Dateien mit + hinzu. Teil antippen und ziehen oder X/Y eingeben. „Automatisch ausrichten“ dreht die Teile und ordnet sie neu an. Oben „Speichern“ erzeugt eine gemeinsame STL. Plattenmaße kommen aus deiner Druckereinrichtung.';
  if (q.contains('leer') || q.contains('bestell') || q.contains('filament')) return 'Im Filamentlager zeigt „Nachbestellen“ die knappen Filamente. Gleiche Rollen werden für die Einkaufsliste zusammengerechnet. Die Grenze ist anpassbar; Restmengen nach dem Drucken aktualisieren.';
  if (q.contains('zapfen') || q.contains('schneid') || q.contains('verbind')) return 'Beim Teilen eines Modells müssen Schnitt, Verbindung und Passung zur Geometrie passen. Zapfen und Gegenloch benötigen ausreichend Material und etwas Spiel. Erst mit einem kleinen Probedruck prüfen, bevor du große Teile druckst.';
  return 'Ich bin eine Offline-Druckhilfe mit hinterlegten Antworten, kein frei antwortender KI-Dienst. Frage mich nach Stützen, Temperaturen, Füllung, Düsen, Slicer-Import, Größe, Druckplatte oder Nachbestellen.';
}
class HelpChatPage extends StatefulWidget {
  const HelpChatPage({super.key,this.project});
  final PrintProject? project;
  @override State<HelpChatPage> createState() => _HelpChatPageState();
}
class _HelpChatPageState extends State<HelpChatPage> {
  final input = TextEditingController(), scroll = ScrollController();
  final messages = <(bool,String)>[(false,'Wobei brauchst du Hilfe? Ich beantworte App- und Druckfragen aus einer hinterlegten Offline-Hilfe.')];
  void ask(String text) {
    if (text.trim().isEmpty) return;
    setState(() { messages.add((true,text.trim())); messages.add((false,answerPrintHelp(text,widget.project))); if (messages.length > 100) messages.removeRange(0,2); });
    input.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) { if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent,duration: const Duration(milliseconds: 200),curve: Curves.easeOut); });
  }
  @override void dispose() { input.dispose(); scroll.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Druckhilfe')),body: SafeArea(top: false,child: Column(children: [
    const Padding(padding: EdgeInsets.all(8),child: Text('Offline · hinterlegte Antworten · keine Übertragung')),
    Expanded(child: ListView(controller: scroll,padding: const EdgeInsets.all(16),children: [
      for (final message in messages) Align(alignment: message.$1 ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(margin: const EdgeInsets.symmetric(vertical: 5),padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: message.$1 ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16)),child: Text(message.$2))),
      Wrap(spacing: 8,children: [for (final topic in ['Stützen','Temperaturen','Düsen','Größe ändern','Slicer-Import','Nachbestellen'])
        ActionChip(label: Text(topic),onPressed: () => ask(topic))]),
    ])),
    Padding(padding: const EdgeInsets.fromLTRB(12,8,12,8),child: Row(children: [
      Expanded(child: TextField(controller: input,maxLength: 1000,decoration: const InputDecoration(hintText: 'Deine Frage',counterText: ''),
        textInputAction: TextInputAction.send,onSubmitted: ask)),
      IconButton(tooltip: 'Frage senden',onPressed: () => ask(input.text),icon: const Icon(Icons.send_rounded)),
    ])),
  ])));
}
