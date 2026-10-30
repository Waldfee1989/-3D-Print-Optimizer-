import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:print_optimizer/project_optimizer.dart';
import 'package:print_optimizer/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

PrintProject part({bool flex = false, bool outdoor = false, bool functional = false}) => PrintProject(
  id: 'test', fileName: 'Modell.stl', dimensions: '20 mm', printer: 'Anycubic Kobra S1',
  slicer: 'Anycubic Slicer Next', nozzle: '0.4', flexible: flex, outdoor: outdoor, functional: functional);

void main() {
  testWidgets('Compact settings show material-specific temperatures and keep explanations collapsed', (tester) async {
    for (final p in [part(), part(functional: true), part(outdoor: true), part(flex: true)]) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
        child: ProjectRecommendation(key: ValueKey(p.advice.material), project: p)))));
      final rows = projectSettings(p);
      expect(find.text('Filament: ${p.advice.material}'), findsOneWidget);
      expect(find.text('Filament-Temperatur: ${rows['Filament-Temperatur']}'), findsOneWidget);
      expect(find.text('Druckbett: ${rows['Druckbett']}'), findsOneWidget);
      expect(find.text(p.advice.reason), findsNothing);
      expect(rows.keys, containsAll(['Kühlung','Rückzug','Haftung','Erste Schicht','Stützen']));
      expect(projectSettingsText(p), contains('Druckbett: ${rows['Druckbett']}'));
      expect(projectSettingsText(p), contains('Importierbare Profile separat als ZIP exportieren.'));
    }
  });
  testWidgets('Home focuses on one model action and inventory remains reachable', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const OptimizerApp());
    await tester.pumpAndSettle();
    expect(find.text('STL / 3MF öffnen'), findsOneWidget);
    expect(find.text('Weitere Funktionen folgen'), findsNothing);
    await tester.scrollUntilVisible(find.text('Filamentlager'), 200);
    await tester.tap(find.text('Filamentlager'));
    await tester.pumpAndSettle();
    expect(find.text('Barcode scannen'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Zur Startseite'));
    await tester.pumpAndSettle();
    expect(find.text('Neues Druckprojekt'), findsOneWidget);
  });
}
