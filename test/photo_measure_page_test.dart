import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:print_optimizer/photo_measure_page.dart';
import 'package:print_optimizer/adapter_request.dart';
import 'package:print_optimizer/adapter_geometry.dart';
import 'package:print_optimizer/app_design.dart';
import 'scroll_helpers.dart';

Future<PhotoInput> fixturePhoto()async{
  final bytes=Uint8List(200*100*4)..fillRange(0,200*100*4,255);
  final complete=Completer<ui.Image>();ui.decodeImageFromPixels(bytes,200,100,ui.PixelFormat.rgba8888,complete.complete);
  return PhotoInput(await complete.future,bytes,'fixture.png');
}
void main(){
  testWidgets('Calibrated photo dimensions transfer explicitly typed ports and leave missing adapter data unanswered',(tester)async{
    tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final photo=await tester.runAsync(fixturePhoto);AdapterDraft? captured;
    await tester.pumpWidget(MaterialApp(theme:studioTheme(),home:Builder(builder:(context)=>Scaffold(body:TextButton(
      onPressed:()async{captured=await Navigator.push<AdapterDraft>(context,MaterialPageRoute(builder:(_)=>PhotoMeasurePage(choose:()async=>photo)));},child:const Text('Öffnen'))))));
    await tester.tap(find.text('Öffnen'));await tester.pumpAndSettle();await tester.tap(find.text('Foto öffnen'));await tester.pumpAndSettle();
    final canvas=find.byKey(const ValueKey('photo-canvas'));
    Future<void> point(double fraction)async{
      await reveal(tester,canvas);final rect=tester.getRect(canvas);
      await tester.tapAt(Offset(rect.left+rect.width*fraction,rect.top+rect.height*.5));await tester.pump();
    }
    await point(.25);await point(.75);
    await reveal(tester,find.byType(TextField));await tester.enterText(find.byType(TextField),'35');
    await reveal(tester,find.text('Referenz übernehmen'));await tester.tap(find.text('Referenz übernehmen'));await tester.pumpAndSettle();
    await point(.1);await point(.9);
    await reveal(tester,find.text('56,0 mm'));expect(find.text('56,0 mm'),findsOneWidget);
    await reveal(tester,find.text('Referenz für Adapter'));await tester.tap(find.text('Referenz für Adapter'));await tester.pumpAndSettle();
    await tester.tap(find.text('Seite A · innen'));await tester.pumpAndSettle();
    await reveal(tester,find.text('Messung für Adapter'));await tester.tap(find.text('Messung für Adapter'));await tester.pumpAndSettle();
    await tester.tap(find.text('Seite B · außen'));await tester.pumpAndSettle();
    await tester.tap(find.text('Zum Adapter'));await tester.pumpAndSettle();
    expect(captured!.first!.diameter,35);expect(captured!.first!.kind,DiameterKind.inner);
    expect(captured!.second!.diameter,56);expect(captured!.second!.kind,DiameterKind.outer);
    expect(captured!.next,AdapterField.length);expect(captured!.wall,isNull);expect(tester.takeException(),isNull);
  });
}
