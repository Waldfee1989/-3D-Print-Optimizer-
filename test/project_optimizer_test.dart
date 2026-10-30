import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:print_optimizer/project_optimizer.dart';

PrintProject sample(String id, {bool outdoor = false, String nozzle = '0.4'}) =>
  PrintProject(id: id, fileName: 'teil.stl', dimensions: '20 × 30 × 10 mm',
    printer: 'Anycubic Kobra S1', slicer: 'Anycubic Slicer Next', nozzle: nozzle,
    outdoor: outdoor);

void main() {
  test('Projects with the same filename stay separate and edits replace only the chosen project', () async {
    SharedPreferences.setMockInitialValues({'stock': '[]', 'qualityMode': 'Maximale Qualität'});
    await savePrintProject(sample('one'));
    await savePrintProject(sample('two'));
    await savePrintProject(sample('one', outdoor: true));
    final rows = await loadPrintProjects();
    expect(rows.length, 2);
    expect(rows.singleWhere((p) => p.id == 'one').advice.material, 'ASA');
    expect(rows.singleWhere((p) => p.id == 'two').advice.material, 'PLA');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('stock'), '[]');
    expect(prefs.getString('qualityMode'), 'Maximale Qualität');
  });
  test('Surface quality overrides fast mode and flex stays flexible under heat', () {
    final p = PrintProject(id: 'x', fileName: 'x.3mf', dimensions: '10 mm',
      printer: 'S1', slicer: 'Next', nozzle: '0.4', priority: 'Schneller Druck',
      highLoad: true, flexible: true, warm: true);
    expect(p.advice.material, 'TPU');
    expect(p.advice.layer, '0,12 mm');
    expect(p.advice.walls, 5);
    expect(p.advice.notes, contains('konkreten TPU'));
    final restored = PrintProject.fromJson(jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);
    expect(restored.toJson(), p.toJson());
  });
  testWidgets('Save stays in the top bar while scrolling and result can be reopened and edited', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(home: MediaQuery(
      data: const MediaQueryData(padding: EdgeInsets.only(bottom: 48)),
      child: ProjectOptimizerPage(project: sample('one')))));
    await tester.tap(find.text('Mechanisches Teil / Gebrauchsteil'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Was hat Vorrang?'), 200);
    expect(tester.getCenter(find.text('Speichern')).dy, lessThan(100));
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Deine Druckempfehlung'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Empfohlenes Material: PETG'), -200);
    expect(find.text('Empfohlenes Material: PETG'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: PrintProjectsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('teil.stl'));
    await tester.pumpAndSettle();
    expect(find.text('Empfohlenes Material: PETG'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Antworten ändern'), 300);
    await tester.tap(find.text('Antworten ändern'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Dauerhaft draußen / in der Sonne'), -300);
    await tester.tap(find.text('Dauerhaft draußen / in der Sonne'));
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect((await loadPrintProjects()).single.advice.material, 'ASA');
  });
  testWidgets('Failed storage preserves answers and does not claim saved', (tester) async {
    SharedPreferences.setMockInitialValues({projectStorageKey: 'broken JSON'});
    await tester.pumpWidget(MaterialApp(home: ProjectOptimizerPage(project: sample('one'))));
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Was ist dir wichtig?'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('Speichern fehlgeschlagen.'), 200);
    expect(find.textContaining('Speichern fehlgeschlagen.'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(projectStorageKey), 'broken JSON');
  });
  testWidgets('Nonstandard nozzle does not show numeric 0.4 mm settings', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      SingleChildScrollView(child: ProjectRecommendation(project: sample('one', nozzle: '0.6'))))));
    expect(find.textContaining('Schichthöhe:'), findsNothing);
    expect(find.textContaining('Für diese Düsengröße'), findsOneWidget);
  });
}
