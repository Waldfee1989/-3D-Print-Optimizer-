import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:print_optimizer/app_design.dart';
import 'package:print_optimizer/build_plate.dart';
import 'package:print_optimizer/model_cut.dart';
import 'geometry_fixtures.dart';
import 'scroll_helpers.dart';

void main(){
  final part=PlatePart(name:'Test',vertices:denseCube(1),unitScale:20,width:40,depth:40,height:40);
  testWidgets('Cut selection returns real thread parameters and removes irrelevant inputs',(tester)async{
    CutSettings? saved;
    await tester.pumpWidget(MaterialApp(theme:studioTheme(),home:Builder(builder:(context)=>Scaffold(body:TextButton(
      onPressed:()async{saved=await showDialog<CutSettings>(context:context,builder:(_)=>CutDialog(part,1,null));},child:const Text('Öffnen'))))));
    await tester.tap(find.text('Öffnen'));await tester.pumpAndSettle();
    await tester.tap(find.text('Schraubgewinde'));await tester.pumpAndSettle();
    await tester.tap(find.text('Teilen'));await tester.pumpAndSettle();
    expect(saved!.connection,2);expect(saved!.diameter,10);expect(saved!.length,8);expect(saved!.pitch,2);
    await tester.tap(find.text('Öffnen'));await tester.pumpAndSettle();
    final play=find.widgetWithText(TextFormField,'Spiel je Seite');
    await reveal(tester,play);await tester.enterText(play,'ungueltig');
    await reveal(tester,find.text('Ohne Verbindung'));
    await tester.tap(find.text('Ohne Verbindung'));await tester.pumpAndSettle();
    expect(find.byType(TextFormField),findsNothing);
    await tester.tap(find.text('Teilen'));await tester.pumpAndSettle();expect(saved!.connection,0);
    expect(tester.takeException(),isNull);
  });
  testWidgets('Snap dialog fits phone and keeps confirmation above the keyboard',(tester)async{
    tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    CutSettings? result;
    await tester.pumpWidget(MaterialApp(theme:studioTheme(),home:Builder(builder:(context)=>Scaffold(body:TextButton(
      onPressed:()async{result=await showDialog<CutSettings>(context:context,builder:(_)=>CutDialog(part,1,null));},child:const Text('Öffnen'))))));
    await tester.tap(find.text('Öffnen'));await tester.pumpAndSettle();
    await tester.tap(find.text('Klickverschluss'));await tester.pumpAndSettle();
    tester.view.viewInsets=const FakeViewPadding(bottom:300);addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.text('Teilen')).dy,lessThan(544));
    await tester.tap(find.text('Teilen'));await tester.pumpAndSettle();
    expect(result!.connection,3);expect(result!.diameter,6);expect(result!.length,10);
    expect(tester.takeException(),isNull);
  });
  testWidgets('Thread length rejects less than three pitches',(tester)async{
    await tester.pumpWidget(MaterialApp(theme:studioTheme(),home:Scaffold(body:CutDialog(part,1,null))));
    await tester.tap(find.text('Schraubgewinde'));await tester.pumpAndSettle();
    final length=find.widgetWithText(TextFormField,'Länge');
    await reveal(tester,length);await tester.enterText(length,'3');
    await tester.tap(find.text('Teilen'));await tester.pumpAndSettle();
    expect(find.text('Mindestens drei Gewindesteigungen lang.'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
}
