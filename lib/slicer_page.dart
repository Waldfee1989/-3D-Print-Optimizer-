import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_design.dart';
import 'local_slicer.dart';
import 'studio_project.dart';
import 'gcode_preview.dart';
import 'project_optimizer.dart';
import 'cloud_send_page.dart';

class SlicerPage extends StatefulWidget {
  const SlicerPage({super.key,required this.project,this.run});
  final StudioProject project;
  final Future<LocalSliceResult> Function(StudioProject)? run;
  @override State<SlicerPage> createState()=>_SlicerPageState();
}
class _SlicerPageState extends State<SlicerPage>{
  final engine=LocalSlicer();
  LocalSliceResult? result;
  bool busy=true,leaving=false,exporting=false;String? error;
  @override void initState(){super.initState();start();}
  Future<void> start()async{
    setState((){busy=true;error=null;});
    try{
      final value=await(widget.run?.call(widget.project)??engine.run(widget.project));
      if(!mounted){await value.directory.delete(recursive:true);return;}
      setState((){result=value;busy=false;});
    }catch(e){if(mounted)setState((){busy=false;error=e is FormatException?e.message:e is PlatformException?e.message:'Slicing fehlgeschlagen. Modell und Einstellungen prüfen.';});}
  }
  Future<void> leave()async{
    if(leaving||exporting)return;
    setState(()=>leaving=true);
    if(busy){try{await engine.cancel();}catch(_){}}
    if(mounted){await WidgetsBinding.instance.endOfFrame;if(mounted)Navigator.pop(context);}
  }
  Future<void> export()async{
    final output=result;if(output==null||exporting)return;
    setState(()=>exporting=true);
    try{
      final name=widget.project.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'),'_');
      bool saved;
      if(Platform.isAndroid){
        saved=await slicerChannel.invokeMethod<bool>('export',{'path':output.path,'name':'$name.gcode'})??false;
      }else{
        final target=await FilePicker.platform.saveFile(dialogTitle:'G-Code speichern',fileName:'$name.gcode',type:FileType.custom,allowedExtensions:['gcode']);
        saved=target!=null;
        if(target!=null)await File(output.path).copy(target);
      }
      if(saved&&mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('G-Code gespeichert.')));
    }catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('G-Code konnte nicht gespeichert werden. Speicherplatz prüfen.')));}
    finally{if(mounted)setState(()=>exporting=false);}
  }
  Future<void> sources()async{
    final info=await PackageInfo.fromPlatform();
    final url=Uri.parse('https://github.com/Waldfee1989/-3D-Print-Optimizer-/releases/download/build-${info.buildNumber}/CuraEngine-source.zip');
    await launchUrl(url,mode:LaunchMode.externalApplication);
  }
  @override void dispose(){if(busy)engine.cancel().catchError((_){ });final directory=result?.directory;if(directory!=null)directory.delete(recursive:true).catchError((_)=>directory);super.dispose();}
  @override Widget build(BuildContext context){
    final preview=result?.preview,p=widget.project,recipe=p.recipe;
    return PopScope(canPop:(!busy&&!exporting)||leaving,onPopInvokedWithResult:(didPop,result){if(!didPop)leave();},child:Scaffold(
      appBar:AppBar(title:Text(busy?'Slicer':'Schichtvorschau'),leading:IconButton(tooltip:busy?'Berechnung abbrechen':'Zurück',onPressed:exporting?null:leave,icon:const Icon(Icons.arrow_back)),actions:[
        TextButton.icon(onPressed:result==null||exporting?null:export,icon:const Icon(Icons.save_alt,size:19),label:Text(exporting?'Speichern …':'G-Code')),
        PopupMenuButton<String>(tooltip:'Slicer-Informationen',onSelected:(v){if(v=='source'){sources();}else{showLicensePage(context:context);}},itemBuilder:(_)=>const[
          PopupMenuItem(value:'source',child:Text('Slicer-Quellcode herunterladen')),PopupMenuItem(value:'license',child:Text('Open-Source-Lizenzen')),
        ]),
      ]),body:SafeArea(top:false,child:ListView(padding:const EdgeInsets.all(20),children:[
        Text(p.name,style:const TextStyle(fontWeight:FontWeight.w800,fontSize:21)),
        Text('${p.printer} · ${p.nozzle} mm',style:const TextStyle(color:studioMuted)),
        if(busy)const Padding(padding:EdgeInsets.symmetric(vertical:65),child:Column(children:[
          CircularProgressIndicator(),SizedBox(height:24),Text('Druckbahnen werden lokal berechnet.'),SizedBox(height:8),Text('Große Modelle brauchen länger. Abbrechen ist oben möglich.',textAlign:TextAlign.center),
        ])),
        if(error!=null)Card(child:Padding(padding:const EdgeInsets.all(20),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Icon(Icons.error_outline,color:Theme.of(context).colorScheme.error),const SizedBox(height:12),Text(error!),const SizedBox(height:14),
          FilledButton(onPressed:start,child:const Text('Erneut berechnen')),
        ]))),
        if(preview!=null)...[
          const SizedBox(height:16),
          FilledButton.icon(onPressed:exporting?null:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>CloudSendPage(file:File(result!.path),projectName:p.name,material:p.recipe!.advice.material))),icon:const Icon(Icons.cloud_upload_outlined),label:const Text('An Drucker senden')),
          const SizedBox(height:20),
          if(preview.seconds!=null||preview.filamentMetres!=null)Card(child:Padding(padding:const EdgeInsets.all(16),child:Wrap(spacing:20,runSpacing:10,children:[
            if(preview.seconds!=null)Text('Druckzeit: ${(preview.seconds!/3600).floor()} h ${((preview.seconds!%3600)/60).ceil()} min'),
            if(preview.filamentMetres!=null)Text('Filament: ${preview.filamentMetres!.toStringAsFixed(2)} m'),
            const Text('Schätzwerte des Slicers',style:TextStyle(fontSize:12,color:studioMuted)),
          ]))),
          const SizedBox(height:16),LayerPreview(preview:preview,bed:p.bed),
          if(recipe!=null)...[
            const StudioHeading('Verwendete Startwerte'),
            Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('Filament: ${recipe.advice.material}'),
              Text('Filament-Temperatur: ${materialTemperatures(recipe.advice.material)!.nozzle} °C'),
              Text('Druckbett: ${materialTemperatures(recipe.advice.material)!.bed} °C'),
              Text('Schichthöhe: ${projectNozzleGeometry(recipe).layer} mm'),
              const Text('Stützen: automatisch · 50°'),
              const Text('Lokaler Slicer: CuraEngine 4.13.1'),
            ]))),
          ],
          const SizedBox(height:12),const Text('Vor dem ersten Druck mit einem kleinen Testmodell beginnen. „An Drucker senden“ bietet Anycubic-Cloud für unterwegs und WLAN vor Ort. Ein Cloud-Upload und der spätere Druckauftrag werden getrennt bestätigt.',style:TextStyle(fontSize:12)),
        ],
      ]))));
  }
}
