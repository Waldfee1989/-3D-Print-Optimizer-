import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'plate_geometry.dart';
import 'printer_setup.dart';
import 'project_optimizer.dart';

const maxProjectBytes=128*1024*1024;
class StudioProject {
  const StudioProject({required this.id,required this.name,required this.printer,required this.slicer,
    required this.nozzle,required this.bed,required this.parts,this.recipe});
  final String id,name,printer,slicer,nozzle;
  final PrinterBed bed;
  final List<PlatePlacement> parts;
  final PrintProject? recipe;
  StudioProject copy({String? id,String? name,PrintProject? recipe,List<PlatePlacement>? parts})=>StudioProject(
    id:id??this.id,name:name??this.name,printer:printer,slicer:slicer,nozzle:recipe?.nozzle??nozzle,bed:bed,parts:parts??this.parts,recipe:recipe??this.recipe);
}

Map<String,dynamic> projectManifest(StudioProject p)=>{
  'format':'print-optimizer-project','version':1,'id':p.id,'name':p.name,'printer':p.printer,'slicer':p.slicer,
  'nozzle':p.nozzle,'bed':p.bed.toJson(),'recipe':p.recipe?.toJson(),
  'parts':[for(var i=0;i<p.parts.length;i++){
    'id':p.parts[i].id,'name':p.parts[i].part.name,'geometry':'geometry/$i.f32','unitScale':p.parts[i].part.unitScale,
    'x':p.parts[i].x,'y':p.parts[i].y,'scale':p.parts[i].scale,'turns':p.parts[i].turns,
  }],
};
Uint8List encodeStudioProject(StudioProject project){
  if(project.parts.isEmpty||project.parts.length>64||!project.bed.valid)throw const FormatException('Projekt ist leer oder zu groß.');
  final archive=Archive();var total=0;
  for(var i=0;i<project.parts.length;i++){
    final vertices=project.parts[i].part.vertices;
    total+=vertices.lengthInBytes;
    if(total>maxProjectBytes-1024*1024||vertices.length%9!=0)throw const FormatException('Projektgeometrie ist zu groß.');
    Uint8List bytes;
    if(Endian.host==Endian.little){bytes=vertices.buffer.asUint8List(vertices.offsetInBytes,vertices.lengthInBytes);}
    else{final data=ByteData(vertices.lengthInBytes);for(var j=0;j<vertices.length;j++){data.setFloat32(j*4,vertices[j],Endian.little);}bytes=data.buffer.asUint8List();}
    archive.addFile(ArchiveFile('geometry/$i.f32',bytes.length,bytes));
  }
  final manifest=utf8.encode(jsonEncode(projectManifest(project)));
  archive.addFile(ArchiveFile('manifest.json',manifest.length,manifest));
  final bytes=Uint8List.fromList(ZipEncoder().encode(archive)!);
  if(bytes.length>maxProjectBytes)throw const FormatException('Projektdatei ist zu groß.');
  return bytes;
}

// Check declared expanded sizes before any decompression. This format uses ZIP32
// only; no paths are ever extracted to the filesystem.
void validateProjectZip(Uint8List bytes){
  if(bytes.length<22||bytes.length>maxProjectBytes)throw const FormatException('Ungültige Projektgröße.');
  final data=ByteData.sublistView(bytes);var end=-1;
  for(var i=bytes.length-22;i>=math.max(0,bytes.length-65557);i--){
    if(data.getUint32(i,Endian.little)==0x06054b50){end=i;break;}
  }
  if(end<0||data.getUint16(end+4,Endian.little)!=0||data.getUint16(end+6,Endian.little)!=0)throw const FormatException('Kein unterstütztes Projektarchiv.');
  final count=data.getUint16(end+10,Endian.little),start=data.getUint32(end+16,Endian.little);
  if(count<2||count>65||start>=end)throw const FormatException('Ungültiger Projektinhalt.');
  var offset=start,total=0;final names=<String>{};
  for(var i=0;i<count;i++){
    if(offset+46>end||data.getUint32(offset,Endian.little)!=0x02014b50)throw const FormatException('Beschädigtes Projektarchiv.');
    final size=data.getUint32(offset+24,Endian.little),nameLength=data.getUint16(offset+28,Endian.little);
    final next=offset+46+nameLength+data.getUint16(offset+30,Endian.little)+data.getUint16(offset+32,Endian.little);
    if(next>end||size==0xffffffff||size>maxProjectBytes)throw const FormatException('Projektdatei ist zu groß.');
    final name=utf8.decode(bytes.sublist(offset+46,offset+46+nameLength));
    if(name.startsWith('/')||name.contains('\\')||name.split('/').contains('..')||!names.add(name))throw const FormatException('Ungültiger Projektpfad.');
    if(name=='manifest.json'&&size>1024*1024)throw const FormatException('Projektbeschreibung ist zu groß.');
    total+=size;if(total>maxProjectBytes)throw const FormatException('Entpacktes Projekt ist zu groß.');offset=next;
  }
  if(!names.contains('manifest.json'))throw const FormatException('Projektbeschreibung fehlt.');
}
StudioProject decodeStudioProject(Uint8List bytes){
  validateProjectZip(bytes);
  final archive=ZipDecoder().decodeBytes(bytes);
  final files={for(final file in archive)file.name:file};
  final manifest=files['manifest.json']!;
  final raw=jsonDecode(utf8.decode(manifest.content as List<int>));
  if(raw is! Map||raw['format']!='print-optimizer-project'||raw['version']!=1)throw const FormatException('Unbekannte Projektversion.');
  final map=Map<String,dynamic>.from(raw);
  String text(String key){final value=map[key];if(value is! String||value.isEmpty||value.length>500)throw const FormatException('Ungültige Projektbeschreibung.');return value;}
  final bed=PrinterBed.fromJson(Map<String,dynamic>.from(map['bed'] as Map));
  if(!bed.valid)throw const FormatException('Ungültiger Bauraum.');
  final rows=map['parts'];if(rows is! List||rows.isEmpty||rows.length>64)throw const FormatException('Ungültige Teileliste.');
  final parts=<PlatePlacement>[],ids=<String>{};
  for(var n=0;n<rows.length;n++){
    final row=Map<String,dynamic>.from(rows[n] as Map);
    final path=row['geometry'];if(path!='geometry/$n.f32'||!files.containsKey(path))throw const FormatException('Modelldaten fehlen.');
    final file=files[path]!;
    if(file.size==0||file.size%36!=0)throw const FormatException('Ungültige Modelldaten.');
    final data=Uint8List.fromList(file.content as List<int>);
    if(data.length!=file.size)throw const FormatException('Unvollständige Modelldaten.');
    final vertices=Float32List(data.length~/4),reader=ByteData.sublistView(data);
    final minimum=[double.infinity,double.infinity,double.infinity],maximum=[double.negativeInfinity,double.negativeInfinity,double.negativeInfinity];
    for(var i=0;i<vertices.length;i++){
      final value=reader.getFloat32(i*4,Endian.little);
      if(!value.isFinite||value.abs()>1e6)throw const FormatException('Ungültige Modellkoordinaten.');
      vertices[i]=value;minimum[i%3]=math.min(minimum[i%3],value);maximum[i%3]=math.max(maximum[i%3],value);
    }
    double number(String key,double low,double high){final v=row[key];if(v is! num||!v.isFinite||v<low||v>high)throw const FormatException('Ungültige Teilposition oder Größe.');return v.toDouble();}
    final unit=number('unitScale',1e-9,1e6),scale=number('scale',.001,1000),x=number('x',-1e6,1e6),y=number('y',-1e6,1e6);
    for(var i=0;i<3;i++)if((maximum[i]+minimum[i]).abs()>1e-3)throw const FormatException('Nicht zentrierte Projektgeometrie.');
    final id=row['id'],name=row['name'],turns=row['turns'];
    if(id is! String||id.length>100||!ids.add(id)||name is! String||name.length>500||turns is! int||turns<0||turns>3)throw const FormatException('Ungültige Teilbeschreibung.');
    parts.add(PlatePlacement(id:id,part:PlatePart(name:name,vertices:vertices,unitScale:unit,
      width:(maximum[0]-minimum[0])*unit,depth:(maximum[1]-minimum[1])*unit,height:(maximum[2]-minimum[2])*unit),
      x:x,y:y,scale:scale,turns:turns));
  }
  return StudioProject(id:text('id'),name:text('name'),printer:text('printer'),slicer:text('slicer'),nozzle:text('nozzle'),bed:bed,parts:parts,
    recipe:map['recipe'] is Map?PrintProject.fromJson(Map<String,dynamic>.from(map['recipe'] as Map)):null);
}

class ProjectSummary {
  const ProjectSummary(this.id,this.name,this.printer,this.count,this.updated);
  final String id,name,printer;final int count;final DateTime updated;
}
class StudioProjectRepository {
  StudioProjectRepository({this.directory});
  final Directory? directory;
  Future<Directory> root()async{
    final d=directory??Directory('${(await getApplicationDocumentsDirectory()).path}/print_projects');
    await d.create(recursive:true);return d;
  }
  String safeId(String id){if(!RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(id))throw const FormatException('Ungültige Projektkennung.');return id;}
  Future<File> target(String id)async=>File('${(await root()).path}/${safeId(id)}.printproject');
  Future<void> atomicWrite(File file,List<int> bytes)async{
    final temp=File('${file.path}.tmp'),backup=File('${file.path}.bak');
    await temp.writeAsBytes(bytes,flush:true);
    if(await file.exists())await file.rename(backup.path);
    try{await temp.rename(file.path);}catch(_){if(await backup.exists())await backup.rename(file.path);rethrow;}
    if(await backup.exists())await backup.delete();
  }
  Future<void> save(StudioProject p)async{
    final bytes=await compute(encodeStudioProject,p),file=await target(p.id);
    await atomicWrite(file,bytes);
    final summary={'id':p.id,'name':p.name,'printer':p.printer,'count':p.parts.length,'updated':DateTime.now().toUtc().toIso8601String()};
    await atomicWrite(File('${file.path}.json'),utf8.encode(jsonEncode(summary)));
  }
  Future<StudioProject> load(String id)async{
    final file=await target(id),backup=File('${(await target(id)).path}.bak');
    if(!await file.exists()&&await backup.exists())await backup.rename(file.path);
    if(await file.length()>maxProjectBytes)throw const FormatException('Projektdatei ist zu groß.');
    return compute(decodeStudioProject,await file.readAsBytes());
  }
  Future<List<ProjectSummary>> list()async{
    final result=<ProjectSummary>[];
    await for(final file in (await root()).list()){
      if(file is! File||!file.path.endsWith('.printproject'))continue;
      final id=file.uri.pathSegments.last.replaceFirst('.printproject','');
      try{
        final raw=jsonDecode(await File('${file.path}.json').readAsString()) as Map;
        result.add(ProjectSummary(id,raw['name'] as String,raw['printer'] as String,raw['count'] as int,DateTime.parse(raw['updated'] as String)));
      }catch(_){result.add(ProjectSummary(id,'Gespeichertes Projekt','',0,(await file.stat()).modified));}
    }
    result.sort((a,b)=>b.updated.compareTo(a.updated));return result;
  }
}
