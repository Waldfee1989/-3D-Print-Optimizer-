import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:print_optimizer/studio_project.dart';
import 'package:print_optimizer/workspace_history.dart';
import 'package:print_optimizer/plate_geometry.dart';
import 'package:print_optimizer/printer_setup.dart';
import 'package:print_optimizer/project_optimizer.dart';
import 'geometry_fixtures.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  final model=PlatePart(name:'Verbindung.stl',vertices:denseCube(1),unitScale:10,width:20,depth:20,height:20);
  StudioProject project()=>StudioProject(id:'fixture',name:'Zwei Teile',printer:'Anycubic Kobra S1',slicer:'Anycubic Slicer Next',nozzle:'0.4',
    bed:const PrinterBed(250,250,250),parts:[PlatePlacement(id:'first',part:model,x:30,y:40,scale:1.5,turns:1),PlatePlacement(id:'second',part:model,x:140,y:180,scale:.75,turns:3)],
    recipe:PrintProject(id:'fixture',fileName:'Zwei Teile',dimensions:'2 Teile',printer:'Anycubic Kobra S1',slicer:'Anycubic Slicer Next',nozzle:'0.4',functional:true,warm:true));
  test('Complete archive restores independent meshes, transforms, bed and recipe',(){
    final original=project(),restored=decodeStudioProject(encodeStudioProject(project()));
    expect(restored.parts.length,2);expect(restored.parts[0].x,30);expect(restored.parts[1].y,180);
    expect(restored.parts[0].scale,1.5);expect(restored.parts[1].turns,3);
    expect(restored.parts[0].part.vertices,original.parts[0].part.vertices);
    expect(restored.parts[0].part.width,20);expect(restored.bed.height,250);
    expect(restored.recipe!.warm,isTrue);expect(restored.recipe!.functional,isTrue);
  });
  test('Imported project gets an independent settings identity',(){
    final original=project(),imported=project().copy(id:'imported_copy');
    expect(imported.recipe!.id,'imported_copy');expect(original.recipe!.id,'fixture');
    expect(imported.parts[0].part.vertices,original.parts[0].part.vertices);
  });
  test('Private project storage reopens without any source model files',()async{
    final directory=await Directory.systemTemp.createTemp('optimizer-project-');
    addTearDown(()=>directory.delete(recursive:true));final repo=StudioProjectRepository(directory:directory);
    await repo.save(project());expect((await repo.list()).single.count,2);
    final restored=await repo.load('fixture');expect(restored.parts.first.part.vertices,model.vertices);
    expect(()=>repo.safeId('../other'),throwsFormatException);
  });
  test('Undo shares geometry, restores deleted parts and clears redo after a new edit',(){
    final history=WorkspaceHistory(),before=PlateSnapshot(project().parts,0);
    history.record(before);
    final moved=PlateSnapshot([before.parts[0].copy(x:90),before.parts[1]],0);
    final undo=history.undo(moved);expect(undo.parts[0].x,30);expect(identical(undo.parts[0].part.vertices,model.vertices),isTrue);
    expect(history.redo(undo).parts[0].x,90);
    history.record(moved);final removed=PlateSnapshot([moved.parts[0]],0);
    expect(history.undo(removed).parts.length,2);
    history.record(before);expect(history.canRedo,isFalse);
  });
}
