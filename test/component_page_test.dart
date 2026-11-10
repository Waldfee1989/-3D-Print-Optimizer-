import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:print_optimizer/adapter_page.dart';
import 'package:print_optimizer/component_geometry.dart';
import 'package:print_optimizer/component_page.dart';
import 'package:print_optimizer/plate_geometry.dart';
import 'scroll_helpers.dart';

void main() {
  testWidgets(
    'Form selection replaces diameter questions and allows returning to adapter',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: AdapterPage()));
      await tester.tap(find.byType(DropdownButtonFormField<ComponentShape>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eckig / Quader').last);
      await tester.pumpAndSettle();
      expect(find.text('Breite X (mm)'), findsOneWidget);
      expect(find.textContaining('Welchen Durchmesser'), findsNothing);
      await tester.tap(find.byType(DropdownButtonFormField<ComponentShape>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Runder Übergang / Adapter').last);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Welchen Durchmesser braucht Seite A'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Quader creates and returns the confirmed dimensions, editing clears old preview',
    (tester) async {
      PlatePart? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.push<PlatePart>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ComponentBuilderPage(
                        shape: ComponentShape.box,
                        chooser: SizedBox(),
                      ),
                    ),
                  );
                },
                child: const Text('Öffnen'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Öffnen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Erstellen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Bitte Breite'), findsOneWidget);
      Future<void> edit(int i, String value) async {
        final field = find.byKey(ValueKey('component-dimension-$i'));
        await reveal(tester, field);
        await tester.enterText(field, value);
        await tester.pumpAndSettle();
      }

      await edit(0, '2 cm');
      await edit(1, '30');
      await edit(2, '5');
      Future<void> create() async {
        await tester.tap(find.text('Erstellen'));
        for (
          var i = 0;
          i < 100 && find.text('Übernehmen').evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(find.text('Übernehmen'), findsOneWidget);
      }

      await create();
      await edit(0, '25');
      expect(find.text('Übernehmen'), findsNothing);
      await create();
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      expect(result!.width, 25);
      expect(result!.depth, 30);
      expect(result!.height, 5);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Free contour starts empty and can undo or clear points', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ComponentBuilderPage(
          shape: ComponentShape.contour,
          chooser: SizedBox(),
        ),
      ),
    );
    final canvas = find.byKey(const ValueKey('contour-canvas'));
    await reveal(tester, canvas);
    await tester.tap(canvas);
    await tester.pump();
    await reveal(tester, find.text('Letzten Punkt entfernen'));
    await tester.tap(find.text('Letzten Punkt entfernen'));
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Kontur löschen'))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}
