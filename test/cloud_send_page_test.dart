import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:print_optimizer/anycubic_cloud.dart';
import 'package:print_optimizer/cloud_login_page.dart';
import 'package:print_optimizer/cloud_send_page.dart';
import 'scroll_helpers.dart';

class FakeCloud extends AnycubicCloudClient {
  FakeCloud(): super('synthetic-test-session-never-used-on-network');
  int reads = 0, uploads = 0, starts = 0;
  bool failStart = false, failList = false, emptyList = false;
  CloudPrinter get printer => CloudPrinter({'id': 41, 'name': 'Test-Kobra', 'model': 'Kobra S1', 'device_status': 1, 'is_printing': 2,
    'multi_color_box': [{'id': 0, 'slots': [{'index': 0, 'type': 'PLA', 'color': [10, 20, 30], 'edit_status': 0}]}]});
  @override Future<List<CloudPrinter>> listPrinters() async { reads++; if (failList) throw const FormatException('Die Druckerliste konnte nicht bestätigt werden (Cloud-Code 500).'); return emptyList ? [] : [printer]; }
  @override Future<CloudPrinter> refreshPrinter(int id) async { reads++; return printer; }
  @override Future<CloudFile> upload(File file, String filename, {void Function(int, int)? progress}) async {
    uploads++; progress?.call(10, 10); return CloudFile.test(202, filename, 10, this);
  }
  @override Future<String> startPrint(CloudFile file, CloudPrinter printer, String material, int? slotIndex, {required bool confirmed}) async {
    expect(confirmed, true); expect(material, 'PLA'); expect(slotIndex, 0);
    file.startAttempted = true; starts++;
    if (failStart) throw const FormatException('Auftragsbestätigung ist unklar. Status prüfen.');
    return 'synthetic-job';
  }
}

Future<void> selectPrinter(WidgetTester tester) async {
  await reveal(tester, find.byType(DropdownButtonFormField<int>).first);
  await tester.tap(find.byType(DropdownButtonFormField<int>).first); await tester.pumpAndSettle();
  await tester.tap(find.text('Test-Kobra').last); await tester.pumpAndSettle();
}

void main() {
  setUp(() { CloudConnection.client = null; });
  tearDown(() { CloudConnection.client = null; });
  testWidgets('Failed printer list is distinct from a successful empty list and can be retried', (tester) async {
    final cloud = FakeCloud()..failList = true;
    await tester.pumpWidget(MaterialApp(home: CloudSendPage(file: File('not-read.gcode'), projectName: 'Testteil', material: 'PLA', initialClient: cloud,
      signIn: () async => null)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kein unterstützter Kobra S1'), findsNothing);
    expect(find.textContaining('Cloud-Code 500'), findsOneWidget);
    cloud..failList = false..emptyList = true;
    await tester.tap(find.text('Druckerliste laden')); await tester.pumpAndSettle();
    expect(find.textContaining('Kein unterstützter Kobra S1'), findsOneWidget);
    expect(find.textContaining('Cloud-Code 500'), findsNothing);
    cloud.emptyList = false;
    await tester.tap(find.text('Druckerliste laden')); await tester.pumpAndSettle();
    expect(find.textContaining('Kein unterstützter Kobra S1'), findsNothing);
    await selectPrinter(tester);
    expect(cloud.uploads, 0); expect(cloud.starts, 0);
  });
  testWidgets('Login, selecting printer and upload never auto-start; print needs slot and separate confirmation', (tester) async {
    tester.view.physicalSize = const Size(390, 844); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final cloud = FakeCloud();
    await tester.pumpWidget(MaterialApp(home: CloudSendPage(file: File('not-read.gcode'), projectName: 'Testteil', material: 'PLA',
      signIn: () async => const CloudLoginResult('synthetic-test-session-for-widget', null), makeClient: (_) => cloud)));
    await tester.pumpAndSettle();
    expect(cloud.reads, 0); expect(cloud.uploads, 0); expect(cloud.starts, 0);
    await tester.tap(find.text('Bei Anycubic anmelden')); await tester.pumpAndSettle();
    expect(cloud.uploads, 0); expect(cloud.starts, 0);
    await selectPrinter(tester);
    await reveal(tester, find.text('Datei in Cloud hochladen')); await tester.tap(find.text('Datei in Cloud hochladen')); await tester.pumpAndSettle();
    expect(cloud.uploads, 0);
    await tester.tap(find.text('Jetzt hochladen')); await tester.pumpAndSettle();
    expect(cloud.uploads, 1); expect(cloud.starts, 0);
    await reveal(tester, find.text('Druckauftrag senden'));
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Druckauftrag senden')).onPressed, isNull);
    await reveal(tester, find.byType(DropdownButtonFormField<int>).last);
    await tester.tap(find.byType(DropdownButtonFormField<int>).last); await tester.pumpAndSettle();
    await tester.tap(find.text('Platz 1: PLA').last); await tester.pumpAndSettle();
    await reveal(tester, find.text('Druckauftrag senden')); await tester.tap(find.text('Druckauftrag senden')); await tester.pumpAndSettle();
    expect(cloud.starts, 0);
    await tester.tap(find.text('Abbrechen')); await tester.pumpAndSettle(); expect(cloud.starts, 0);
    await tester.tap(find.text('Druckauftrag senden')); await tester.pumpAndSettle();
    await tester.tap(find.text('Druckauftrag bestätigen')); await tester.pumpAndSettle();
    expect(cloud.starts, 1);
    await reveal(tester, find.textContaining('Die Anycubic-Cloud hat den Druckauftrag angenommen.'));
    expect(find.textContaining('bitte in der Anycubic-App prüfen.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Uncertain command stays blocked instead of being retried', (tester) async {
    final cloud = FakeCloud()..failStart = true;
    await tester.pumpWidget(MaterialApp(home: CloudSendPage(file: File('not-read.gcode'), projectName: 'Testteil', material: 'PLA', initialClient: cloud,
      signIn: () async => null)));
    await tester.pumpAndSettle(); await selectPrinter(tester);
    await reveal(tester, find.byType(DropdownButtonFormField<int>).last); await tester.tap(find.byType(DropdownButtonFormField<int>).last); await tester.pumpAndSettle();
    await tester.tap(find.text('Platz 1: PLA').last); await tester.pumpAndSettle();
    await reveal(tester, find.text('Datei in Cloud hochladen')); await tester.tap(find.text('Datei in Cloud hochladen')); await tester.pumpAndSettle();
    await tester.tap(find.text('Jetzt hochladen')); await tester.pumpAndSettle();
    await reveal(tester, find.text('Druckauftrag senden')); await tester.tap(find.text('Druckauftrag senden')); await tester.pumpAndSettle();
    await tester.tap(find.text('Druckauftrag bestätigen')); await tester.pumpAndSettle();
    expect(cloud.starts, 1);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Druckauftrag senden')).onPressed, isNull);
    expect(find.textContaining('Die Anycubic-Cloud hat den Druckauftrag angenommen.'), findsNothing);
  });
}
