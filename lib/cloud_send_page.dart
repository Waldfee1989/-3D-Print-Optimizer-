import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'anycubic_cloud.dart';
import 'cloud_login_page.dart';
import 'kobra_lan.dart';
import 'printer_send_page.dart';

class CloudConnection {
  static AnycubicCloudClient? client; // Session only, no preferences or logs.
}

class CloudSendPage extends StatefulWidget {
  const CloudSendPage({super.key, required this.file, required this.projectName, required this.material,
    this.initialClient, this.signIn, this.makeClient});
  final File file;
  final String projectName, material;
  final AnycubicCloudClient? initialClient;
  final Future<CloudLoginResult?> Function()? signIn;
  final AnycubicCloudClient Function(CloudLoginResult)? makeClient;
  @override State<CloudSendPage> createState() => _CloudSendPageState();
}
class _CloudSendPageState extends State<CloudSendPage> {
  AnycubicCloudClient? client;
  List<CloudPrinter> printers = [];
  CloudPrinter? printer;
  CloudFile? uploaded;
  int? slotIndex;
  bool busy = false, external = false;
  double? progress;
  String? error, accepted;
  @override void initState() {
    super.initState(); client = widget.initialClient ?? CloudConnection.client;
    if (client != null) reload();
  }
  void failure(Object e) { if (mounted) setState(() => error = e is FormatException ? e.message : 'Cloud-Aktion fehlgeschlagen. Bitte erneut prüfen.'); }
  Future<void> login() async {
    if (busy) return;
    if (widget.signIn == null && !Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) {
      setState(() => error = 'Die eingebettete Cloud-Anmeldung ist in dieser Version für Android, iOS und macOS vorgesehen.'); return;
    }
    final result = widget.signIn != null ? await widget.signIn!() :
      await Navigator.push<CloudLoginResult>(context, MaterialPageRoute(builder: (_) => const CloudLoginPage()));
    if (result == null || !mounted) return;
    client?.logout(); CloudConnection.client = null;
    setState(() { client = widget.makeClient?.call(result) ?? AnycubicCloudClient(result.token, userAgent: result.userAgent);
      printers = []; printer = null; uploaded = null; accepted = null; slotIndex = null; external = false; });
    await reload();
    if (error == null) CloudConnection.client = client;
  }
  Future<void> reload() async {
    if (busy || client == null) return;
    setState(() { busy = true; error = null; printer = null; slotIndex = null; external = false; });
    try { final value = await client!.listPrinters(); if (mounted) setState(() => printers = value);
    } catch (e) { failure(e);
    } finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> choose(int? id) async {
    if (busy || id == null || client == null) return;
    setState(() { busy = true; printer = null; slotIndex = null; external = false; error = null; });
    try { final value = await client!.refreshPrinter(id); if (mounted) setState(() => printer = value);
    } catch (e) { failure(e);
    } finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> upload() async {
    if (busy || client == null || printer == null || uploaded != null) return;
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(scrollable: true,
      title: const Text('Datei in die Anycubic-Cloud hochladen?'),
      content: Text('${widget.projectName}\nMaterial: ${widget.material}\n\nDie Druckdatei wird in deinem Anycubic-Konto gespeichert. Dadurch startet noch kein Druck. Der LAN-Modus am Drucker bleibt aus.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Jetzt hochladen'))]));
    if (yes != true || !mounted) return;
    setState(() { busy = true; error = null; progress = 0; });
    try {
      final file = await client!.upload(widget.file, kobraFilename(widget.projectName), progress: (sent, total) {
        if (mounted) setState(() => progress = sent / total);
      });
      if (mounted) setState(() => uploaded = file);
    } catch (e) { failure(e);
    } finally { if (mounted) setState(() { busy = false; progress = null; }); }
  }
  Future<void> startPrint() async {
    final file = uploaded, target = printer;
    if (busy || file == null || target == null || client == null || file.startAttempted || (slotIndex == null && !external)) return;
    final source = external ? 'Externe Rolle' : 'ACE-Platz ${slotIndex! + 1}';
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(scrollable: true,
      title: const Text('Druckauftrag wirklich senden?'),
      content: Text('${target.name}\n${file.name}\n${widget.material} · $source\n\nDer Drucker kann nach Annahme aufheizen und drucken. Bestätige erst, wenn Druckplatte, Filament und Drucker vorbereitet sind. Die Cloud-Anbindung ist eine erste Testversion.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Druckauftrag bestätigen'))]));
    if (yes != true || !mounted) return;
    setState(() { busy = true; error = null; });
    try {
      final message = await client!.startPrint(file, target, widget.material, external ? null : slotIndex, confirmed: true);
      if (mounted) setState(() => accepted = message);
    } catch (e) { failure(e);
    } finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> logout() async {
    if (busy) return;
    client?.logout(); CloudConnection.client = null;
    setState(() { client = null; printer = null; printers = []; uploaded = null; accepted = null; error = null; });
    if (widget.signIn == null && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
      try { await WebViewCookieManager().clearCookies(); await WebViewController().clearLocalStorage(); } catch (_) {}
    }
  }
  @override void dispose() { client?.cancel(); super.dispose(); }
  @override Widget build(BuildContext context) {
    final file = uploaded, target = printer;
    final slots = target == null ? <CloudSlot>[] : cloudSlots(target).where((s) => s.material.toUpperCase() == widget.material.toUpperCase()).toList();
    final boxes = target?.details['multi_color_box'];
    final noAce = target != null && target.details.containsKey('multi_color_box') && (boxes == null || boxes is List && boxes.isEmpty);
    return PopScope(canPop: !busy, child: Scaffold(
      appBar: AppBar(title: const Text('Über Anycubic-Cloud senden'), actions: [
        if (busy) TextButton(onPressed: () => client?.cancel(), child: const Text('Abbrechen')),
      ]), body: SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
        Text(widget.projectName, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        const Text('Von unterwegs senden: Handy mit Internet, Drucker mit seiner Anycubic-Cloud verbunden. LAN-Modus am Drucker ausgeschaltet lassen.'),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: busy ? null : login, icon: const Icon(Icons.account_circle_outlined),
          label: Text(client == null ? 'Bei Anycubic anmelden' : 'Anycubic-Konto neu verbinden')),
        if (client != null) ...[
          TextButton(onPressed: busy ? null : logout, child: const Text('Konto trennen und Anmeldung löschen')),
          OutlinedButton.icon(onPressed: busy ? null : reload, icon: const Icon(Icons.refresh), label: const Text('Druckerliste laden')),
          if (printers.isEmpty && !busy) const Text('Kein unterstützter Kobra S1 im verbundenen Konto gefunden.'),
          if (printers.isNotEmpty) DropdownButtonFormField<int>(key: ValueKey(printer?.id), initialValue: printer?.id,
            decoration: const InputDecoration(labelText: 'Dein Drucker'), isExpanded: true,
            items: [for (final p in printers) DropdownMenuItem(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis))],
            onChanged: busy || accepted != null ? null : choose),
        ],
        if (target != null) ...[
          const SizedBox(height: 12), Text('${target.name}: ${!target.online ? 'offline' : target.idle ? 'online · bereit' : 'beschäftigt oder Bereitschaft unbekannt'}'),
          Text('Slicer-Material: ${widget.material}'),
          if (slots.isNotEmpty) DropdownButtonFormField<int>(initialValue: slotIndex,
            decoration: const InputDecoration(labelText: 'ACE-Filamentplatz wählen'),
            items: [for (final slot in slots) DropdownMenuItem(value: slot.index, child: Text('Platz ${slot.index + 1}: ${slot.material}'))],
            onChanged: busy || file?.startAttempted == true ? null : (v) => setState(() { slotIndex = v; external = false; })),
          if (noAce) CheckboxListTile(contentPadding: EdgeInsets.zero, title: Text('Externe Rolle mit ${widget.material} ist eingelegt'),
            value: external, onChanged: busy || file?.startAttempted == true ? null : (v) => setState(() { external = v == true; slotIndex = null; })),
          if (!noAce && slots.isEmpty) const Text('Kein passender ACE-Platz aus den Cloud-Daten bestätigt. Der Upload bleibt möglich; der Druckstart wartet auf eine passende Filamentzuordnung.'),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: busy || file != null ? null : upload, icon: const Icon(Icons.cloud_upload_outlined), label: const Text('Datei in Cloud hochladen')),
        ],
        if (busy) ...[const SizedBox(height: 12), LinearProgressIndicator(value: progress), Text(progress == null ? 'Cloud-Anfrage läuft …' : progress! >= 1 ? 'Warte auf Cloud-Bestätigung …' : '${(progress! * 100).floor()} % Dateidaten übergeben')],
        if (file != null) ...[
          const SizedBox(height: 16), Text('In deinem Cloud-Konto gespeichert: ${file.name}'),
          const Text('Der Upload allein hat noch keinen Druck gestartet.'),
          FilledButton.icon(onPressed: busy || target == null || !target.online || !target.idle || file.startAttempted || (slotIndex == null && !external) ? null : startPrint,
            icon: const Icon(Icons.print_outlined), label: const Text('Druckauftrag senden')),
          if (file.startAttempted && accepted == null && !busy) const Text('Der Auftrag wurde bereits versucht. Vor weiteren Aktionen den Status in der Anycubic-App prüfen.'),
        ],
        if (accepted != null) const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Die Anycubic-Cloud hat den Druckauftrag angenommen. Ob der Drucker ihn herunterlädt und ausführt, bitte in der Anycubic-App prüfen.'))),
        if (error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 20),
        const Text('Cloud-Testversion: Anmeldung, Dateiformat und Druckannahme müssen mit deinem Konto geprüft werden. Anycubic kann seine Cloud-Schnittstelle ändern. Bei einer unklaren Auftragsbestätigung den Status in der Anycubic-App prüfen.'),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: busy ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => PrinterSendPage(file: widget.file, projectName: widget.projectName))),
          icon: const Icon(Icons.wifi), label: const Text('Alternativ im selben WLAN senden')),
      ])),
    ));
  }
}
