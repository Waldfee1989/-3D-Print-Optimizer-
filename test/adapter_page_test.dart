import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:print_optimizer/adapter_page.dart';
import 'package:print_optimizer/app_design.dart';
import 'package:print_optimizer/build_plate.dart';

void main(){
  testWidgets('Spoken request asks for each missing dimension before creating geometry',(tester)async{
    PlatePart? result;
    await tester.pumpWidget(MaterialApp(theme:studioTheme(),home:Builder(builder:(context)=>Scaffold(body:TextButton(
      onPressed:()async{result=await Navigator.push<PlatePart>(context,MaterialPageRoute(builder:(_)=>AdapterPage(recognize:()async=>'innen 35 mm und außen 50 mm')));},child:const Text('Öffnen'))))));
    await tester.tap(find.text('Öffnen'));await tester.pumpAndSettle();
    await tester.tap(find.text('Sprechen'));await tester.pumpAndSettle();
    expect(find.text('Wie lang soll der Adapter insgesamt sein? Angabe in Millimetern.'),findsOneWidget);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton,'Erstellen')).onPressed,isNull);
    for(final value in ['60','2,5','15']){
      await tester.enterText(find.byType(TextField),value);await tester.tap(find.text('Angabe übernehmen'));await tester.pumpAndSettle();
    }
    expect(find.text('Sind diese Maße richtig?'),findsOneWidget);expect(find.text('Innendurchmesser 35 mm'),findsOneWidget);expect(find.text('Außendurchmesser 50 mm'),findsOneWidget);
    await tester.tap(find.text('Erstellen'));
    for(var i=0;i<100&&find.text('Übernehmen').evaluate().isEmpty;i++){await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:20)));await tester.pump();}
    expect(find.text('Übernehmen'),findsOneWidget);await tester.tap(find.text('Übernehmen'));await tester.pumpAndSettle();
    expect(result!.width,50);expect(result!.height,60);expect(tester.takeException(),isNull);
  });
  testWidgets('Missing Android speech provider leaves manual entry available',(tester)async{
    await tester.pumpWidget(MaterialApp(theme:studioTheme(),home:AdapterPage(recognize:()async=>throw PlatformException(code:'NO_PROVIDER'))));
    await tester.tap(find.text('Sprechen'));await tester.pumpAndSettle();
    expect(find.textContaining('hier eintippen'),findsOneWidget);expect(find.byType(TextField),findsOneWidget);
    await tester.enterText(find.byType(TextField),'innen 35 mm und außen 50 mm');await tester.tap(find.text('Angabe übernehmen'));await tester.pumpAndSettle();
    expect(find.textContaining('insgesamt sein'),findsOneWidget);expect(tester.takeException(),isNull);
  });
}
