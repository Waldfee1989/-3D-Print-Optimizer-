import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:print_optimizer/kobra_lan.dart';
import 'package:print_optimizer/printer_send_page.dart';

class TestPrinter extends KobraLanClient {
  TestPrinter(): super('192.168.1.50');
  int reads = 0, writes = 0;
  bool reject = false;
  @override Future<KobraLanInfo> inspect() async {
    reads++;
    return KobraLanInfo(ip, 'Anycubic Kobra S1', Uri.parse('http://$ip:18910/gcode_upload'));
  }
  @override Future<String> upload(File file, String filename, {void Function(int sent, int total)? progress}) async {
    writes++;
    if (reject) throw const FormatException('Test: Drucker lehnt Datei ab.');
    progress?.call(20, 20);
    return filename;
  }
}
void main() {
  setUp(() { SharedPreferences.setMockInitialValues({'kobra_s1_lan_ip': '192.168.1.50'}); });
  testWidgets('Connection is read-only and file upload needs explicit confirmation', (tester) async {
    final printer = TestPrinter();
    await tester.pumpWidget(MaterialApp(home: PrinterSendPage(file: File('not-accessed-in-test.gcode'), projectName: 'Wuerfel', clientFactory: (_) => printer)));
    await tester.pumpAndSettle();
    expect(printer.reads, 0); expect(printer.writes, 0);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Druckdatei senden')).onPressed, isNull);
    await tester.tap(find.text('Verbindung prüfen')); await tester.pumpAndSettle();
    expect(printer.reads, 1); expect(printer.writes, 0);
    await tester.ensureVisible(find.text('Druckdatei senden')); await tester.tap(find.text('Druckdatei senden')); await tester.pumpAndSettle();
    expect(printer.writes, 0);
    await tester.tap(find.text('Abbrechen')); await tester.pumpAndSettle(); expect(printer.writes, 0);
    await tester.tap(find.text('Druckdatei senden')); await tester.pumpAndSettle();
    await tester.tap(find.text('Jetzt senden')); await tester.pumpAndSettle();
    expect(printer.writes, 1);
    await tester.ensureVisible(find.textContaining('Der Drucker hat die Übertragung bestätigt.'));
    expect(find.textContaining('Es wurde kein Druck gestartet.'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, 1000)); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '192.168.1.51'); await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Druckdatei senden')).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Rejected file never produces a success message', (tester) async {
    final printer = TestPrinter()..reject = true;
    await tester.pumpWidget(MaterialApp(home: PrinterSendPage(file: File('test.gcode'), projectName: 'Wuerfel', clientFactory: (_) => printer)));
    await tester.pumpAndSettle(); await tester.tap(find.text('Verbindung prüfen')); await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Druckdatei senden')); await tester.tap(find.text('Druckdatei senden')); await tester.pumpAndSettle();
    await tester.tap(find.text('Jetzt senden')); await tester.pumpAndSettle();
    expect(find.textContaining('Der Drucker hat die Übertragung bestätigt.'), findsNothing);
    expect(find.text('Test: Drucker lehnt Datei ab.'), findsOneWidget);
  });
}
