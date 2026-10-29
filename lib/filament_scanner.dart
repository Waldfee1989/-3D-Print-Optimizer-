import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'filament_inventory.dart';

class FilamentScannerPage extends StatefulWidget {
  const FilamentScannerPage({super.key});
  @override State<FilamentScannerPage> createState() => _FilamentScannerPageState();
}

class _FilamentScannerPageState extends State<FilamentScannerPage> {
  final controller = MobileScannerController(detectionSpeed: DetectionSpeed.normal);
  final latch = FilamentScanLatch();

  @override void dispose() {
    controller.dispose().catchError((Object _) {});
    super.dispose();
  }

  void detected(BarcodeCapture capture) {
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return;
    final code = latch.accept(capture.barcodes.map((barcode) => barcode.rawValue));
    if (code == null || !mounted) return;
    controller.stop().catchError((Object _) {});
    Navigator.pop(context, code);
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Filament-Barcode scannen'), actions: [
      IconButton(tooltip: 'Licht umschalten', icon: const Icon(Icons.flashlight_on),
        onPressed: () async {
          try { await controller.toggleTorch(); }
          catch (_) {
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Kameralicht ist nicht verfügbar.')));
          }
        }),
    ]),
    body: Column(children: [
      const Padding(padding: EdgeInsets.all(16),
        child: Text('Halte einen einzelnen Barcode auf der Rolle oder Verpackung vor die Kamera. '
            'Unbekannte Codes kannst du anschließend einer Rolle zuordnen.')),
      Expanded(child: MobileScanner(controller: controller, onDetect: detected,
        useAppLifecycleState: true, tapToFocus: true,
        errorBuilder: (context, error) => const Center(child: Padding(
          padding: EdgeInsets.all(24), child: Text('Kamera nicht verfügbar oder Zugriff nicht erlaubt. '
              'Du kannst den Code unten eintippen oder die Kameraberechtigung in den Android-App-Einstellungen erlauben.'))))),
      SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(16),
        child: OutlinedButton.icon(onPressed: () {
          latch.completed = true;
          Navigator.pop(context, '');
        },
          icon: const Icon(Icons.keyboard), label: const Text('Code eintippen')))),
    ]),
  );
}
