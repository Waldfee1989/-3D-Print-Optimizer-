import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:print_optimizer/app_design.dart';
import 'package:print_optimizer/photo_part_page.dart';
import 'package:print_optimizer/photo_part_service.dart';

Map<String,dynamic> planFixture(String status)=>{
  'name':'Zaun-Testvertrag','summary':'Fester Testvertrag, keine Bilderkennung.','status':status,
  'dimensions':[
    {'id':'reference','label':'Gesamtlänge einschließlich Clips','help':'Von äußerstem Ende bis äußerstem Ende einschließlich Clips messen.','kind':'mm','choices':<String>[],'image_index':0,'a':[.1,.5],'b':[.9,.5]},
    {'id':'pin','label':'Zapfendurchmesser','help':'Nur den kleinen Zapfen messen, nicht den Querpfosten.','kind':'mm','choices':<String>[],'image_index':1,'a':[.4,.3],'b':[.6,.3]},
  ],'operations':status=='ready'?[{'op':'add','kind':'box','size':['reference','pin','2'],'position':['0','0','0'],'rotation':[0,0,0]}]:<Object>[],'assumptions':<String>[],'blockers':<String>[],
};

Uint8List stlFixture(){
  final data=ByteData(84+4*50)..setUint32(80,4,Endian.little);
  final vertices=[[0.0,0.0,0.0],[10.0,0.0,0.0],[0.0,20.0,0.0],[0.0,0.0,30.0]],faces=[[0,2,1],[0,1,3],[0,3,2],[1,2,3]];
  for(var i=0;i<4;i++)for(var j=0;j<3;j++)for(var k=0;k<3;k++)data.setFloat32(84+i*50+12+(j*3+k)*4,vertices[faces[i][j]][k],Endian.little);
  return data.buffer.asUint8List();
}
class FakePhotoService extends PhotoPartService{
  FakePhotoService():super(Uri.parse('https://photo-service.example'), 'test-code-never-used-on-network-123456789');
  int analyses=0,generations=0;Map<String,Object>? lastAnswers;String? clarificationReceived;
  @override Future<PhotoPartPlan> analyze(List<Uint8List> images,Map<String,Object> answers,PhotoPartPlan? previous,{String? clarification})async{
    clarificationReceived=clarification;
    expect(images.length,4);analyses++;lastAnswers=Map.of(answers);
    return PhotoPartPlan.parse(planFixture(answers.length==2?'ready':'need_measurements'),4,previous:previous);
  }
  @override Future<Uint8List> generate(PhotoPartPlan plan,Map<String,Object> answers,int imageCount,bool approved)async{generations++;lastAnswers=Map.of(answers);return stlFixture();}
}
Future<List<PhotoPartImage>> imagesFixture()async{
  final recorder=ui.PictureRecorder();final canvas=Canvas(recorder);canvas.drawRect(const Rect.fromLTWH(10,10,100,60),Paint()..color=Colors.orange);
  final picture=recorder.endRecording(),image=await picture.toImage(120,80);picture.dispose();
  final bytes=(await image.toByteData(format:ui.ImageByteFormat.png))!.buffer.asUint8List();image.dispose();
  return List.generate(10,(i)=>PhotoPartImage('p$i',bytes,120,80));
}
Future<void> reveal(WidgetTester tester,Finder finder)async{
  await tester.drag(find.byType(ListView).first,const Offset(0,3000));await tester.pumpAndSettle();
  await tester.scrollUntilVisible(finder,200,scrollable:find.byType(Scrollable).first,maxScrolls:30);await tester.pumpAndSettle();
}

void main(){
  setUpAll(()async{
    final icons=FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));await icons.load();
    final file=File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
    if(await file.exists()){final loader=FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(await file.readAsBytes())));await loader.load();}
  });
  test('Measurement units, stable meaning and exact STL bounds are validated',(){
    expect(photoLengthMillimetres('15,7 cm'),157);expect(photoLengthMillimetres('2.5mm'),2.5);
    for(final input in ['-2','NaN','Infinity','0','1m','12 oder 20'])expect(photoLengthMillimetres(input),isNull);
    final previous=PhotoPartPlan.parse(planFixture('need_measurements'),4);
    final changed=planFixture('ready');(changed['dimensions'] as List)[0]['label']='Andere Strecke';
    expect(()=>PhotoPartPlan.parse(changed,4,previous:previous),throwsFormatException);
    final wrong=planFixture('ready');(wrong['dimensions'] as List)[0]['image_index']=7;
    expect(()=>PhotoPartPlan.parse(wrong,4),throwsFormatException);
    final part=photoPartFromStl(stlFixture());expect(part.width,10);expect(part.depth,20);expect(part.height,30);
    expect(()=>photoPartFromStl(Uint8List(90)),throwsFormatException);
    expect(()=>PhotoPartService(Uri.parse('http://insecure.example'),List.filled(32,'t').join()),throwsFormatException);
  });
  testWidgets('Manual handoff keeps upload off and copies exact reference notes',(tester)async{
    final photos=(await tester.runAsync(imagesFixture))!;
    await tester.pumpWidget(MaterialApp(home:PhotoPartPage(restoreDraft:false,choose:(_,__)async=>photos.take(4).toList())));
    await tester.pumpAndSettle();
    expect(find.text('Fotos zur Online-Auswertung senden'),findsNothing);
    await reveal(tester,find.text('Anfrage kopieren'));
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'Anfrage kopieren')).onPressed,isNull);
    await reveal(tester,find.text('Fotos laden'));await tester.tap(find.text('Fotos laden'));await tester.pumpAndSettle();
    await reveal(tester,find.text('Bauteil und Maße eintragen'));await tester.tap(find.text('Bauteil und Maße eintragen'));await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField),'Zaun: mit Clips 157 mm; Zapfen 2,5 mm.');
    await tester.tap(find.text('Speichern'));await tester.pumpAndSettle();
    await reveal(tester,find.text('Anfrage kopieren'));await tester.tap(find.text('Anfrage kopieren'));await tester.pumpAndSettle();
    final clipboard=await Clipboard.getData(Clipboard.kTextPlain);
    expect(clipboard?.text,contains('Zaun: mit Clips 157 mm; Zapfen 2,5 mm.'));
    expect(clipboard?.text,contains('4 Fotos'));expect(clipboard?.text,contains('Erfinde keine Maße'));
    expect(find.text('Fotodienst verbinden'),findsNothing);expect(tester.takeException(),isNull);
  });
  testWidgets('Photo workflow requires explicit upload, marks missing dimensions and generates only after reanalysis',(tester)async{
    tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final photos=(await tester.runAsync(imagesFixture))!,service=FakePhotoService(),boundary=GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key:boundary,child:MaterialApp(debugShowCheckedModeBanner:false,theme:studioTheme(),home:PhotoPartPage(service:service,restoreDraft:false,choose:(_,__)async=>photos.take(4).toList()))));await tester.pumpAndSettle();
    await tester.tap(find.text('Fotos laden'));await tester.pumpAndSettle();
    expect(service.analyses,0);expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'Bauteil analysieren')).onPressed,isNull);
    await reveal(tester,find.text('Fotos zur Online-Auswertung senden'));await tester.tap(find.text('Fotos zur Online-Auswertung senden'));await tester.pumpAndSettle();
    await reveal(tester,find.text('Bauteil analysieren'));await tester.tap(find.text('Bauteil analysieren'));await tester.pumpAndSettle();
    for(final entry in [('reference','15,7 cm'),('pin','2,5 mm')]){
      final target=find.byKey(ValueKey('photo-measure-${entry.$1}'));await reveal(tester,target);
      await tester.runAsync(()=>precacheImage(MemoryImage(photos.first.png),tester.element(find.byType(AnnotatedPhotoQuestion))));await tester.pump();
      if(entry.$1=='reference')await tester.runAsync(()async{
        final render=boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary,image=await render.toImage(pixelRatio:1);
        final bytes=await image.toByteData(format:ui.ImageByteFormat.png);image.dispose();if(bytes!=null)print('PHOTO_PART_QUESTION_PNG:${base64Encode(bytes.buffer.asUint8List())}');
      });
      await tester.tap(target);await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('photo-answer-input')),entry.$2);await tester.tap(find.text('Angabe bestätigen'));await tester.pumpAndSettle();
      if(entry.$1=='reference'){
        await reveal(tester,find.text('Messstelle unklar – genauer zeigen'));await tester.tap(find.text('Messstelle unklar – genauer zeigen'));await tester.pumpAndSettle();
        expect(service.clarificationReceived,contains('pin'));expect(service.lastAnswers,{'reference':157.0});
      }
    }
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton,'3D erzeugen')).onPressed,isNull);
    await reveal(tester,find.text('Mit Angaben weiter auswerten'));await tester.tap(find.text('Mit Angaben weiter auswerten'));await tester.pumpAndSettle();
    expect(service.lastAnswers,{'reference':157.0,'pin':2.5});
    await tester.tap(find.text('3D erzeugen'));
    for(var i=0;i<100&&find.text('Übernehmen').evaluate().isEmpty;i++){await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:20)));await tester.pump();}
    expect(service.generations,1);expect(find.text('Übernehmen'),findsOneWidget);expect(find.byTooltip('STL speichern'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());expect(tester.takeException(),isNull);
  });
  testWidgets('Photo selection is capped at eight and never calls analysis by itself',(tester)async{
    final photos=(await tester.runAsync(imagesFixture))!,service=FakePhotoService();
    await tester.pumpWidget(MaterialApp(home:PhotoPartPage(service:service,restoreDraft:false,choose:(_,__)async=>photos)));await tester.pumpAndSettle();
    await tester.tap(find.text('Fotos laden'));await tester.pumpAndSettle();
    expect(find.text('8 von 8 Fotos · mindestens 4'),findsOneWidget);expect(service.analyses,0);
    expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'Fotos laden')).onPressed,isNull);
    expect(tester.takeException(),isNull);
  });
}
