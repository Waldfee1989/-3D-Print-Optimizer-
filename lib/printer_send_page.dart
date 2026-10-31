import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'kobra_lan.dart';

class PrinterSendPage extends StatefulWidget {
  const PrinterSendPage({super.key, required this.file, required this.projectName, this.clientFactory});
  final File file;
  final String projectName;
  final KobraLanClient Function(String ip)? clientFactory;
  @override State<PrinterSendPage> createState() => _PrinterSendPageState();
}

class _PrinterSendPageState extends State<PrinterSendPage> {
  final ip = TextEditingController();
  KobraLanClient? client;
  KobraLanInfo? printer;
  String? error, received;
  bool busy = true;
  double? progress;
  String? filename;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) ip.text = prefs.getString('kobra_s1_lan_ip') ?? '';
    } catch (_) { /* The connection can still be configured without persistence. */
    } finally { if (mounted) setState(() => busy = false); }
  }
  void failed(Object e) {
    if (mounted) setState(() => error = e is FormatException ? e.message : 'Druckerverbindung fehlgeschlagen. Bitte erneut prüfen.');
  }
  Future<void> connect() async {
    setState(() { busy = true; error = null; printer = null; received = null; });
    try {
      final address = kobraLanIp(ip.text);
      final next = widget.clientFactory?.call(address) ?? KobraLanClient(address);
      client = next;
      final info = await next.inspect();
      if (!mounted) return;
      setState(() => printer = info);
      try { await (await SharedPreferences.getInstance()).setString('kobra_s1_lan_ip', address); } catch (_) {}
    } catch (e) { failed(e);
    } finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> send() async {
    if (busy || printer == null || client == null) return;
    final name = kobraFilename(widget.projectName);
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(scrollable: true,
      title: const Text('Datei an Drucker senden?'),
      content: Text('${printer!.name}\n${printer!.ip}\n\n$name\n\nDie Datei wird übertragen. Ein Druck wird dadurch nicht gestartet. Die Annahme und Druckbarkeit des App-G-Codes auf Firmware V2.7.2.7 müssen am Gerät geprüft werden.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Jetzt senden'))]));
    if (yes != true || !mounted) return;
    setState(() { busy = true; error = null; received = null; progress = 0; filename = name; });
    try {
      final value = await client!.upload(widget.file, name, progress: (sent, total) {
        if (mounted) setState(() => progress = sent / total);
      });
      if (mounted) setState(() => received = value);
    } catch (e) { failed(e);
    } finally { if (mounted) setState(() { busy = false; progress = null; }); }
  }
  @override void dispose() { client?.cancel(); ip.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => PopScope(canPop: !busy, child: Scaffold(
    appBar: AppBar(title: const Text('An Drucker senden'), actions: [
      if (busy) TextButton(onPressed: () => client?.cancel(), child: const Text('Abbrechen')),
    ]),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
      Text(widget.projectName, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      const Text('Handy und Kobra S1 müssen im selben WLAN sein. Am Drucker LAN-Modus einschalten und dort die WiFi-IP ablesen. Ein Gastnetz kann die Verbindung blockieren.'),
      const SizedBox(height: 12),
      TextField(controller: ip, enabled: !busy, keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Drucker-IP', hintText: '192.168.1.50'),
        onChanged: (_) => setState(() { printer = null; received = null; error = null; })),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: busy ? null : connect, icon: const Icon(Icons.wifi_find), label: const Text('Verbindung prüfen')),
      if (printer != null) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.print_outlined),
        title: Text(printer!.name), subtitle: Text('Verbunden mit ${printer!.ip}')),
      FilledButton.icon(onPressed: busy || printer == null || received != null ? null : send,
        icon: const Icon(Icons.send_outlined), label: const Text('Druckdatei senden')),
      if (busy) ...[
        const SizedBox(height: 16), LinearProgressIndicator(value: progress),
        Text(progress == null ? 'Verbindung wird geprüft …' : progress! >= 1 ? 'Warte auf Bestätigung des Druckers …' : '${(progress! * 100).floor()} % der Dateidaten übergeben'),
        if (filename != null) Text(filename!),
      ],
      if (error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      if (received != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(
        'Der Drucker hat die Übertragung bestätigt.\n$received\n\nBitte die Datei am Drucker in der Dateiliste prüfen. Es wurde kein Druck gestartet.'))),
      const SizedBox(height: 12),
      const Text('Erste Testversion für den Kobra S1. Der Verbindungstest liest nur Druckerinformationen. Beim Senden gehen Dateidaten direkt an die angezeigte lokale IP; es wird kein Cloud-Dienst verwendet.'),
    ])),
  ));
}
