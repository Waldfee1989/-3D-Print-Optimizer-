import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:print_optimizer/main.dart';
import 'package:print_optimizer/studio_project.dart';
import 'package:print_optimizer/plate_geometry.dart';
import 'package:print_optimizer/printer_setup.dart';
import 'package:print_optimizer/project_optimizer.dart';
import 'package:print_optimizer/local_slicer.dart';
import 'package:print_optimizer/gcode_preview.dart';
import '../test/geometry_fixtures.dart';

void main(){
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Installed Android app generates real G-code and restores its complete project',(tester)async{
    await tester.pumpWidget(const OptimizerApp());await tester.pumpAndSettle();
    final p=StudioProject(id:'android_smoke',name:'Android Slicer Test',printer:'Anycubic Kobra S1',slicer:'Anycubic Slicer Next',nozzle:'0.4',
      bed:const PrinterBed(250,250,250),parts:[PlatePlacement(id:'cube',part:PlatePart(name:'cube.stl',vertices:denseCube(1),unitScale:10,width:20,depth:20,height:20),x:110,y:110)],
      recipe:PrintProject(id:'android_smoke',fileName:'cube.stl',dimensions:'20 mm',printer:'Anycubic Kobra S1',slicer:'Anycubic Slicer Next',nozzle:'0.4',surface:'Standard',priority:'Schneller Druck'));
    final repository=StudioProjectRepository();await repository.save(p);
    final restored=await repository.load(p.id);expect(restored.parts.single.x,110);
    final result=await LocalSlicer().run(restored);
    expect(result.preview.layers.length,inInclusiveRange(95,105));expect(result.preview.extrusionMoves,greaterThan(300));expect(result.preview.outsideBed,isFalse);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:SingleChildScrollView(child:LayerPreview(preview:result.preview,bed:p.bed)))));
    await tester.pumpAndSettle();expect(find.textContaining('Schicht 1 /'),findsOneWidget);expect(tester.takeException(),isNull);
    await result.directory.delete(recursive:true);
  },timeout:const Timeout(Duration(minutes:5)));
}
