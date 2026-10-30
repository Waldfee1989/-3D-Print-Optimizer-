import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:print_optimizer/build_plate.dart';
import 'package:print_optimizer/printer_setup.dart';
import 'package:print_optimizer/print_geometry.dart';
import 'package:print_optimizer/support_analysis.dart';
import 'geometry_fixtures.dart';

class SavePicker extends FilePicker {
  Uint8List? captured;
  @override Future<String?> saveFile({String? dialogTitle,String? fileName,String? initialDirectory,
    FileType type=FileType.any,List<String>? allowedExtensions,Uint8List? bytes,bool lockParentWindow=false}) async {
    captured=bytes;return null;
  }
}
PlatePart cube(String name)=>PlatePart(name:name,vertices:denseCube(1),unitScale:10,width:20,depth:20,height:20);
List<double> xRange(Uint8List bytes,int first,int count) {
  final data=ByteData.sublistView(bytes);var min=double.infinity,max=double.negativeInfinity;
  for(var f=first;f<first+count;f++)for(var k=0;k<3;k++){
    final x=data.getFloat32(84+f*50+12+k*12,Endian.little);if(x<min)min=x;if(x>max)max=x;
  }return[min,max];
}
void main(){
  test('Combined STL keeps independent positions, scales and all triangles',(){
    final placements=[PlatePlacement(id:'a',part:cube('A'),x:30,y:30,scale:2),PlatePlacement(id:'b',part:cube('B'),x:150,y:150,scale:.5)];
    final bytes=encodePlateStl(placements);
    expect(ByteData.sublistView(bytes).getUint32(80,Endian.little),24);
    expect(xRange(bytes,0,12),[10,50]);expect(xRange(bytes,12,12),[145,155]);
    expect(placements[0].fits(250,250,30),isFalse);
    final next=placeNextPart(cube('C'),placements,250,250,'c');
    expect(placements.every((p)=>!p.bounds.overlaps(next.bounds)),isTrue);
  });
  test('Bed-aware orientation can turn an elongated model in XY and rejects impossible beds',(){
    final source=denseCube(1);final v=Float32List(source.length);
    for(var i=0;i<v.length;i++)v[i]=source[i]*(i%3==0?150:i%3==1?100:50);
    final assessment=assessSupports(v);
    expect(fittingPrintOrientation(v,assessment,1,const PrinterBed(250,350,250)),6);
    expect(fittingPrintOrientation(v,assessment,1,const PrinterBed(10,10,10)),isNull);
  });
  test('Automatic orientation keeps scales and gives valid per-part geometry',(){
    final v=pyramid(inverted:true);
    final p=PlatePart(name:'Kopf',vertices:v,unitScale:10,width:20,depth:20,height:3);
    final result=autoOrientPlate(([PlatePlacement(id:'a',part:p,x:30,y:30,scale:2)],250.0,250.0,250.0));
    expect(result.$2,0);expect(result.$1.single.scale,2);
    expect(assessSupports(result.$1.single.part.vertices).status,'Voraussichtlich keine Stützen nötig');
  });
  testWidgets('Adding and dragging a second part leaves the first part unchanged in exported STL',(tester) async {
    tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final picker=SavePicker();FilePicker.platform=picker;
    final first=placeNextPart(cube('A'),[],250,250,'0');
    final second=placeNextPart(cube('B'),[first],250,250,'1');
    await tester.pumpWidget(MaterialApp(home:BuildPlatePage(initialPart:cube('A'),pickPart:()async=>cube('B'))));
    await tester.pumpAndSettle();await tester.tap(find.byTooltip('Datei hinzufügen'));await tester.pumpAndSettle();
    await tester.drag(find.byKey(const ValueKey('plate-hit-1')),const Offset(30,0));await tester.pump();
    await tester.tap(find.text('Speichern'));await tester.pumpAndSettle();await tester.tap(find.text('STL exportieren'));
    await tester.pump();
    for(var i=0;i<100&&picker.captured==null;i++){await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:20)));await tester.pump();}
    expect(picker.captured,isNotNull);
    expect(xRange(picker.captured!,0,12),[first.x-10,first.x+10]);
    expect(xRange(picker.captured!,12,12).first,greaterThan(second.x-10));
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
