import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:print_optimizer/material_advice.dart';

void main() {
  MaterialAdvice advice({bool part = false, bool outside = false, bool load = false,
    bool flex = false, bool heat = false, String mode = 'Maximale Qualität'}) =>
      recommendMaterial(functional: part, outdoor: outside, highLoad: load,
        flexible: flex, warm: heat, quality: mode);
  test('Indoor defaults, functional parts and exposed parts have distinct recommendations', () {
    expect(advice().material, 'PLA');
    expect(advice(part: true).material, 'PETG');
    expect(advice(load: true).material, 'PETG');
    expect(advice(outside: true).material, 'ASA');
    expect(advice(heat: true).material, 'ASA');
    expect(advice(outside: true).notes, contains('Abluft'));
    expect(advice(load: true).walls, greaterThan(advice().walls));
  });
  test('Flexibility wins over rigid materials but heat and sun stay qualified', () {
    final result = advice(flex: true, outside: true, heat: true, load: true);
    expect(result.material, 'TPU');
    expect(result.notes, contains('konkreten TPU'));
    expect(result.notes, contains('Belastbarkeit'));
    expect(advice().layer, '0,12 mm');
    expect(advice(mode: 'Ausgewogen').layer, '0,16 mm');
    expect(advice(mode: 'Schneller Druck').layer, '0,20 mm');
  });
  testWidgets('Answers update the result, persist separately and reload without altering stock', (tester) async {
    SharedPreferences.setMockInitialValues({'stock': '[]', 'qualityMode': 'Maximale Qualität'});
    await tester.pumpWidget(const MaterialApp(home: MaterialAdvicePage(quality: 'Maximale Qualität', nozzle: '0.4')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Materialvorschlag: PLA'), 200);
    await tester.scrollUntilVisible(find.text('Dauerhaft draußen / in der Sonne'), -200);
    await tester.tap(find.text('Dauerhaft draußen / in der Sonne'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Materialvorschlag: ASA'), 200);
    await tester.scrollUntilVisible(find.text('Antworten merken'), 200);
    await tester.tap(find.text('Antworten merken'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('stock'), '[]');
    expect(prefs.getString('qualityMode'), 'Maximale Qualität');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const MaterialApp(home: MaterialAdvicePage(quality: 'Maximale Qualität', nozzle: '0,4')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Materialvorschlag: ASA'), 200);
    expect(find.text('Materialvorschlag: ASA'), findsOneWidget);
  });
}
