import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:print_optimizer/adapter_page.dart';
import 'package:print_optimizer/app_design.dart';
import 'package:print_optimizer/build_plate.dart';
import 'package:print_optimizer/adapter_geometry.dart';
import 'package:print_optimizer/adapter_request.dart';

void main(){
  testWidgets('Spoken request asks for each missing dimension before creating geometry',(tester)async{
    PlatePart? result;
    await tester.pumpWidget(MaterialApp(theme:studioTheme(),home:Builder(builder:(context)=>Scaffold(body:TextButton(
      onPressed:()async{result=await Navigator.push<PlatePart>(context,MaterialPageRoute(builder:(_)=>AdapterPage(recognize:()async=>'innen 35 mm und außen 50 mm')));},child:const Text('Öffnen'))))));
    await tester.tap(find.text('Öffnen'));await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sprechen'));await tester.tap(find.text('Sprechen'));await tester.pumpAndSettle();
    expect(find.text('Wie lang soll das Bauteil insgesamt sein? Angabe in Millimetern.'),findsOneWidget);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton,'Erstellen')).onPressed,isNull);
    for(final value in ['60','2,5','15']){
      await tester.ensureVisible(find.byType(TextField));await tester.enterText(find.byType(TextField),value);await tester.ensureVisible(find.text('Angabe übernehmen'));await tester.tap(find.text('Angabe übernehmen'));await tester.pumpAndSettle();
    }
    expect(find.text('Sind diese Maße richtig?'),findsOneWidget);expect(find.text('Innendurchmesser 35 mm'),findsOneWidget);expect(find.text('Außendurchmesser 50 mm'),findsOneWidget);
    await tester.tap(find.text('Erstellen'));
    for(var i=0;i<100&&find.text('Übernehmen').evaluate().isEmpty;i++){await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:20)));await tester.pump();}
    expect(find.text('Übernehmen'),findsOneWidget);await tester.tap(find.text('Übernehmen'));await tester.pumpAndSettle();
    expect(result!.width,50);expect(result!.height,60);expect(tester.takeException(),isNull);
  });
  testWidgets('Missing Android speech provider leaves manual entry available',(tester)async{
    await tester.pumpWidget(MaterialApp(theme:studioTheme(),home:AdapterPage(recognize:()async=>throw PlatformException(code:'NO_PROVIDER'))));
    await tester.ensureVisible(find.text('Sprechen'));await tester.tap(find.text('Sprechen'));await tester.pumpAndSettle();
    expect(find.textContaining('hier eintippen'),findsOneWidget);expect(find.byType(TextField),findsOneWidget);
    await tester.enterText(find.byType(TextField),'innen 35 mm und außen 50 mm');await tester.tap(find.text('Angabe übernehmen'));await tester.pumpAndSettle();
    expect(find.textContaining('insgesamt sein'),findsOneWidget);expect(tester.takeException(),isNull);
  });
  testWidgets('Sketch edits one confirmed dimension, converts centimetres and preserves other dimensions',(tester)async{
    final draft=AdapterDraft()..first=const AdapterPort(DiameterKind.inner,35)..second=const AdapterPort(DiameterKind.outer,50)..length=60..wall=2.5..socket=15;
    await tester.pumpWidget(MaterialApp(theme:studioTheme(),home:AdapterPage(initialDraft:draft)));
    await tester.tap(find.text('Maß in Skizze eintragen'));await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sketch-length')));await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('sketch-dimension-input')),'6,8 cm');
    await tester.tap(find.text('Maß speichern'));await tester.pumpAndSettle();
    expect(draft.length,68);expect(draft.first!.diameter,35);expect(draft.second!.diameter,50);expect(draft.wall,2.5);expect(draft.socket,15);
    await tester.tap(find.byKey(const ValueKey('sketch-wall')));await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('sketch-dimension-input')),'50');await tester.tap(find.text('Maß speichern'));await tester.pumpAndSettle();
    expect(find.textContaining('Maß zwischen'),findsOneWidget);expect(draft.wall,2.5);
    await tester.tap(find.text('Abbrechen'));await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Skizze schließen'));await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton,'Erstellen')).onPressed,isNotNull);expect(tester.takeException(),isNull);
  });
  testWidgets('Sketch requires explicit diameter kind and blocks contradictory length and socket dimensions',(tester)async{
    final draft=AdapterDraft()..second=const AdapterPort(DiameterKind.outer,50)..length=60..wall=2.5..socket=15;
    await tester.pumpWidget(MaterialApp(theme:studioTheme(),home:AdapterPage(initialDraft:draft)));
    await tester.tap(find.text('Maß in Skizze eintragen'));await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sketch-first')));await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('sketch-dimension-input')),'35');await tester.tap(find.text('Maß speichern'));await tester.pumpAndSettle();
    expect(draft.first,isNull);expect(find.textContaining('ausdrücklich'),findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip,'Innenmaß'));await tester.tap(find.text('Maß speichern'));await tester.pumpAndSettle();
    expect(draft.first!.kind,DiameterKind.inner);
    await tester.tap(find.byKey(const ValueKey('sketch-socket')));await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('sketch-dimension-input')),'40');await tester.tap(find.text('Maß speichern'));await tester.pumpAndSettle();
    expect(find.textContaining('mindestens zweimal Stecktiefe'),findsOneWidget);
    await tester.tap(find.byTooltip('Skizze schließen'));await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton,'Erstellen')).onPressed,isNull);expect(draft.length,60);expect(tester.takeException(),isNull);
  });
}
