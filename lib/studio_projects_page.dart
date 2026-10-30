import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'studio_project.dart';
import 'build_plate.dart';
import 'project_optimizer.dart';
import 'app_design.dart';

class StudioProjectsPage extends StatefulWidget {
  const StudioProjectsPage({super.key,required this.pickPart,this.repository});
  final Future<PlatePart?> Function() pickPart;
  final StudioProjectRepository? repository;
  @override State<StudioProjectsPage> createState()=>_StudioProjectsPageState();
}
class _StudioProjectsPageState extends State<StudioProjectsPage>{
  late final repository=widget.repository??StudioProjectRepository();
  List<ProjectSummary>? projects;
  bool busy=false;String? error;
  @override void initState(){super.initState();load();}
  Future<void> load()async{try{final rows=await repository.list();if(mounted)setState(()=>projects=rows);}catch(_){if(mounted)setState(()=>error='Projekte konnten nicht geladen werden.');}}
  Future<void> showProject(StudioProject p)async{
    if(!mounted)return;
    await Navigator.push(context,MaterialPageRoute(builder:(_)=>BuildPlatePage(pickPart:widget.pickPart,project:p,repository:repository)));
    if(mounted)await load();
  }
  Future<void> open(String id)async{
    setState((){busy=true;error=null;});
    try{final p=await repository.load(id);if(mounted){setState(()=>busy=false);await showProject(p);}}
    catch(_){if(mounted)setState(()=>error='Projekt konnte nicht geöffnet werden.');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> import()async{
    setState((){busy=true;error=null;});
    try{
      final chosen=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['printproject'],withData:false);
      if(chosen==null)return;final file=chosen.files.single;
      if(file.size>maxProjectBytes)throw const FormatException('Projektdatei ist zu groß.');
      if(file.path!=null&&await File(file.path!).length()>maxProjectBytes)throw const FormatException('Projektdatei ist zu groß.');
      final bytes=file.bytes??(file.path==null?null:await File(file.path!).readAsBytes());
      if(bytes==null||bytes.length>maxProjectBytes)throw const FormatException('Datei konnte nicht geladen werden.');
      final p=(await compute(decodeStudioProject,bytes)).copy(id:DateTime.now().microsecondsSinceEpoch.toString());
      await repository.save(p);
      if(mounted){setState(()=>busy=false);await showProject(p);}
    }catch(e){if(mounted)setState(()=>error=e is FormatException?e.message:'Projektdatei konnte nicht importiert werden.');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Druckprojekte'),actions:[
    IconButton(tooltip:'Projektdatei öffnen',onPressed:busy?null:import,icon:const Icon(Icons.file_open_outlined)),
  ]),body:SafeArea(top:false,child:ListView(padding:const EdgeInsets.all(20),children:[
    const StudioHeading('Alles an einem Ort',subtitle:'Modelle, Druckplatte und Einstellungen zusammen.'),
    if(busy)const LinearProgressIndicator(),
    if(error!=null)Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
    if(projects==null&&!busy)const Center(child:CircularProgressIndicator()),
    if(projects?.isEmpty??false)Card(child:Padding(padding:const EdgeInsets.all(24),child:Column(children:[
      const Icon(Icons.folder_copy_outlined,size:42,color:studioPurple),const SizedBox(height:12),
      const Text('Noch kein vollständiges Projekt gespeichert.'),const SizedBox(height:12),
      OutlinedButton.icon(onPressed:busy?null:import,icon:const Icon(Icons.file_open_outlined),label:const Text('Projektdatei öffnen')),
    ]))),
    for(final p in projects??<ProjectSummary>[])Card(child:ListTile(contentPadding:const EdgeInsets.all(14),
      leading:const CircleAvatar(child:Icon(Icons.view_in_ar_rounded)),title:Text(p.name),
      subtitle:Text('${p.count} Teile · ${p.printer}'),trailing:const Icon(Icons.chevron_right),onTap:busy?null:()=>open(p.id))),
    const SizedBox(height:20),TextButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const PrintProjectsPage())),
      icon:const Icon(Icons.history),label:const Text('Frühere Einstellungen ohne Modelldateien')),
  ])));
}
