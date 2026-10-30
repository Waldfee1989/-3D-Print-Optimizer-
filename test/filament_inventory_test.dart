import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:print_optimizer/filament_inventory.dart';
import 'package:print_optimizer/main.dart';
import 'scroll_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Remembered product survives an empty inventory without copying roll balance', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await FilamentCatalog(prefs).remember({'barcode': ' 0012345 ', 'brand': 'SUNLU',
      'material': 'PLA+', 'color': 'Schwarz', 'grams': 143.5});
    final profile = FilamentCatalog(prefs).lookup('0012345', []);
    expect(profile, {'brand': 'SUNLU', 'material': 'PLA+', 'color': 'Schwarz'});
    expect(profile!.containsKey('grams'), isFalse);
    expect(FilamentCatalog(prefs).lookup('12345', []), isNull);
    await FilamentCatalog(prefs).remember({'barcode': '0012345', 'brand': 'SUNLU',
      'material': 'PETG', 'color': 'Blau', 'grams': 999});
    expect(FilamentCatalog(prefs).lookup('0012345', [])!['material'], 'PETG');
  });

  test('Existing saved stock provides a profile when no catalog exists', () async {
    SharedPreferences.setMockInitialValues({FilamentCatalog.storageKey: 'broken JSON'});
    final prefs = await SharedPreferences.getInstance();
    final old = {'barcode': 'ABC', 'brand': 'Other', 'material': 'PLA', 'color': 'Rot', 'grams': 77};
    expect(FilamentCatalog(prefs).lookup(' ABC ', [old])!['brand'], 'Other');
    expect(FilamentCatalog(prefs).lookup('abc', [old]), isNull);
    expect(old['grams'], 77);
  });

  test('One scan result is accepted once and ambiguous frames do not choose a product', () {
    final latch = FilamentScanLatch();
    expect(latch.accept([null, ' ']), isNull);
    expect(latch.accept(['123', '456']), isNull);
    expect(latch.accept([' 00123 ', '00123']), '00123');
    expect(latch.accept(['00123']), isNull);
    expect(latch.accept(['new']), isNull);
  });

  Future<void> openCode(WidgetTester tester, String code) async {
    if (find.text('Filamentcode eingeben').evaluate().isEmpty) {
      await reveal(tester,find.text('Filamentlager'));
      await tester.tap(find.text('Filamentlager'));
      await tester.pumpAndSettle();
    }
    await reveal(tester,find.text('Filamentcode eingeben'));
    await tester.tap(find.text('Filamentcode eingeben'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), code);
    await tester.tap(find.text('Suchen'));
    await tester.pumpAndSettle();
  }

  testWidgets('Unknown code defaults SUNLU; separate rolls keep separate balances and edit safely', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    await openCode(tester, '0012345');
    var fields = find.byType(TextFormField);
    expect(tester.widget<TextFormField>(fields.at(1)).controller!.text, 'SUNLU');
    await tester.enterText(fields.at(3), 'Schwarz');
    await tester.enterText(fields.at(4), '142,5');
    await tester.tap(find.text('Hinzufügen'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    List<dynamic> rolls() => jsonDecode(prefs.getString('stock')!) as List;
    expect(rolls().single['grams'], 142.5);

    await openCode(tester, '0012345');
    await tester.tap(find.text('Neue Rolle'));
    await tester.pumpAndSettle();
    fields = find.byType(TextFormField);
    expect(tester.widget<TextFormField>(fields.at(3)).controller!.text, 'Schwarz');
    expect(tester.widget<TextFormField>(fields.at(4)).controller!.text, '1000');
    await tester.tap(find.text('Hinzufügen'));
    await tester.pumpAndSettle();
    expect(rolls().map((r) => r['grams']).toList(), [142.5, 1000.0]);

    await openCode(tester, '0012345');
    await tester.tap(find.text('Rolle 1: SUNLU PLA Schwarz'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(4), '23,4');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(rolls().map((r) => r['grams']).toList(), [23.4, 1000.0]);

    await openCode(tester, '0012345');
    await tester.tap(find.text('Neue Rolle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(rolls().length, 2);
  });

  testWidgets('Invalid balances cannot be saved; zero and comma decimals are supported', (tester) async {
    Map<String, dynamic>? saved;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () async {
        saved = await showDialog<Map<String, dynamic>>(context: context,
          builder: (_) => const FilamentEditor(barcode: '001',
            profile: {'brand': 'SUNLU', 'material': 'PLA', 'color': 'Weiß'}));
      }, child: const Text('Öffnen'))))));
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();
    final amount = find.byType(TextFormField).at(4);
    for (final value in ['-1', 'NaN', 'Infinity', 'abc', '']) {
      await tester.enterText(amount, value);
      await tester.tap(find.text('Hinzufügen'));
      await tester.pumpAndSettle();
      expect(find.text('Bitte eine gültige Restmenge ab 0 g eintragen.'), findsOneWidget);
      expect(saved, isNull);
    }
    await tester.enterText(amount, '0');
    await tester.tap(find.text('Hinzufügen'));
    await tester.pumpAndSettle();
    expect(saved!['grams'], 0);
  });
}
