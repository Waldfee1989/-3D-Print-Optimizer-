import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'app_design.dart';
import 'mesh_renderer.dart';
import 'plate_geometry.dart';
import 'photo_part_service.dart';

class PhotoPartImage {
  const PhotoPartImage(this.id,this.png,this.width,this.height);
  final String id;final Uint8List png;final int width,height;
  static Future<PhotoPartImage> fromFile(XFile file,String id)async{
    if(await file.length()>25*1024*1024)throw const FormatException('Ein Foto darf höchstens 25 MB groß sein.');
    return decode(await file.readAsBytes(),id);
  }
  static Future<PhotoPartImage> decode(Uint8List bytes,String id)async{
    if(bytes.length>25*1024*1024)throw const FormatException('Ein Foto darf höchstens 25 MB groß sein.');
    final buffer=await ui.ImmutableBuffer.fromUint8List(bytes);ui.ImageDescriptor? descriptor;ui.Codec? codec;ui.Image? image;
    try{
      descriptor=await ui.ImageDescriptor.encoded(buffer);
      if(descriptor.width<8||descriptor.height<8||descriptor.width*descriptor.height>80000000)throw const FormatException('Fotoauflösung nicht unterstützt.');
      final factor=math.min(1,1200/math.max(descriptor.width,descriptor.height));
      codec=await descriptor.instantiateCodec(targetWidth:math.max(1,(descriptor.width*factor).round()),targetHeight:math.max(1,(descriptor.height*factor).round()));
      image=(await codec.getNextFrame()).image;final data=await image.toByteData(format:ui.ImageByteFormat.png);
      if(data==null)throw const FormatException('Foto konnte nicht gelesen werden.');
      return PhotoPartImage(id,Uint8List.fromList(data.buffer.asUint8List(data.offsetInBytes,data.lengthInBytes)),image.width,image.height);
    }finally{image?.dispose();codec?.dispose();descriptor?.dispose();buffer.dispose();}
  }
}

class PhotoPartPage extends StatefulWidget {
  const PhotoPartPage({super.key,this.service,this.choose,this.restoreDraft=true});
  final PhotoPartService? service;
  final Future<List<PhotoPartImage>> Function(bool camera,int capacity)? choose;
  final bool restoreDraft;
  @override State<PhotoPartPage> createState()=>_PhotoPartPageState();
}
class _PhotoPartPageState extends State<PhotoPartPage>{
  final photos=<PhotoPartImage>[],answers=<String,Object>{};
  PhotoPartPlan? plan;PhotoPartService? service;String? error,selected;
  bool busy=false,consent=false,approved=false,needsAnalysis=true;
  Uint8List? stl;PlatePart? part;
  Directory? directory;
  Future<void> writes=Future<void>.value();
  @override void initState(){super.initState();service=widget.service;initialize();}
  Future<void> initialize()async{
    setState(()=>busy=true);
    try{
      if(widget.restoreDraft){
        directory=Directory('${(await getApplicationDocumentsDirectory()).path}/photo_part_draft');await directory!.create(recursive:true);
        final file=File('${directory!.path}/draft.json'),backup=File('${directory!.path}/draft.bak');
        if(!await file.exists()&&await backup.exists())await backup.rename(file.path);
        if(await file.exists()){
          if(await file.length()>1024*1024)throw const FormatException('Fotoentwurf ist zu groß.');
          final saved=jsonDecode(await file.readAsString()) as Map;final images=saved['photos'] as List;
          if(images.length>8)throw const FormatException('Zu viele Fotos im Entwurf.');
          for(final entry in images){
            final id=entry as String;if(!RegExp(r'^p[0-9_]+$').hasMatch(id))throw const FormatException('Ungültiger Fotoentwurf.');
            final image=File('${directory!.path}/$id.png');if(await image.length()>6*1024*1024)throw const FormatException('Fotoentwurf ist zu groß.');
            photos.add(await PhotoPartImage.decode(await image.readAsBytes(),id));
          }
          if(saved['plan']!=null)plan=PhotoPartPlan.parse(Map<String,dynamic>.from(saved['plan'] as Map),photos.length);
          final values=Map<String,dynamic>.from(saved['answers'] as Map);
          if(values.length>32||values.values.any((v)=>v is! String&&v is! num))throw const FormatException('Ungültige gespeicherte Maße.');
          for(final entry in values.entries){answers[entry.key]=entry.value as Object;}
          needsAnalysis=saved['needs_analysis']!=false;
        }
      }
      if(Platform.isAndroid&&widget.choose==null){
        final lost=await ImagePicker().retrieveLostData();
        if(lost.files!=null){for(final file in lost.files!.take(8-photos.length)){
          photos.add(await PhotoPartImage.fromFile(file,'p${DateTime.now().microsecondsSinceEpoch}_${photos.length}'));
        }needsAnalysis=true;await persist();}
      }
    }catch(_){error='Der vorherige Fotoentwurf konnte nicht vollständig geladen werden. Bitte die Fotos prüfen.';}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> persist(){
    final target=directory;if(target==null)return Future<void>.value();
    final images=List<PhotoPartImage>.of(photos),metadata=jsonEncode({'photos':photos.map((p)=>p.id).toList(),'plan':plan?.json,'answers':answers,'needs_analysis':needsAnalysis});
    final operation=writes.then((_)async{
      for(final photo in images){final file=File('${target.path}/${photo.id}.png');if(!await file.exists())await file.writeAsBytes(photo.png,flush:true);}
      final file=File('${target.path}/draft.json'),temporary=File('${target.path}/draft.tmp'),backup=File('${target.path}/draft.bak');
      await temporary.writeAsString(metadata,flush:true);
      if(await backup.exists())await backup.delete();if(await file.exists())await file.rename(backup.path);
      await temporary.rename(file.path);if(await backup.exists())await backup.delete();
    });
    writes=operation.catchError((Object _){});return operation;
  }
  void failure(Object e){if(mounted)setState(()=>error=e is FormatException?e.message:'Die Aktion konnte nicht beendet werden. Bitte erneut versuchen.');}
  Future<void> addPhotos(bool camera)async{
    if(photos.length>=8)return;
    setState((){busy=true;error=null;});
    try{
      final capacity=8-photos.length;
      List<PhotoPartImage> additions;
      if(widget.choose!=null){additions=await widget.choose!(camera,capacity);}
      else{
        final picker=ImagePicker();final files=<XFile>[];
        if(camera){final f=await picker.pickImage(source:ImageSource.camera,maxWidth:1200,maxHeight:1200,imageQuality:85);if(f!=null)files.add(f);}
        else{files.addAll(await picker.pickMultiImage(maxWidth:1200,maxHeight:1200,imageQuality:85));}
        additions=[];for(final file in files.take(capacity)){
          additions.add(await PhotoPartImage.fromFile(file,'p${DateTime.now().microsecondsSinceEpoch}_${additions.length}'));
        }
      }
      if(!mounted)return;
      setState((){photos.addAll(additions.take(capacity));if(additions.isNotEmpty){needsAnalysis=true;approved=false;part=null;stl=null;}});await persist();
    }catch(e){failure(e);}finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> configure()async{
    final url=TextEditingController(text:const String.fromEnvironment('PHOTO_PART_SERVICE_URL')),code=TextEditingController();String? problem;
    final route=DialogRoute<PhotoPartService>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,refresh)=>AlertDialog(scrollable:true,
      title:const Text('Fotodienst verbinden'),content:Column(mainAxisSize:MainAxisSize.min,children:[
        const Text('Für die Bauteilerkennung wird ein eingerichteter Online-Fotodienst benötigt. Hier gehört dessen Zugangscode hinein, kein ChatGPT-Passwort und kein OpenAI-API-Schlüssel.'),
        TextField(controller:url,decoration:const InputDecoration(labelText:'HTTPS-Adresse des Fotodienstes'),keyboardType:TextInputType.url),
        TextField(controller:code,obscureText:true,decoration:const InputDecoration(labelText:'Zugangscode des Fotodienstes')),
        if(problem!=null)Text(problem!,style:TextStyle(color:Theme.of(ctx).colorScheme.error)),
      ]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Abbrechen')),FilledButton(onPressed:(){try{Navigator.pop(ctx,PhotoPartService(Uri.parse(url.text.trim()),code.text.trim()));}catch(_){refresh(()=>problem='Gültige HTTPS-Adresse und Zugangscode des Fotodienstes eintragen.');}},child:const Text('Verbinden'))],
    )));
    final value=await Navigator.of(context).push(route);await route.completed;
    url.dispose();code.dispose();
    if(value!=null&&mounted)setState(()=>service=value);
  }
  Future<void> analyze()async{
    if(photos.length<4||!consent)return;
    if(service==null){await configure();if(service==null||!mounted)return;}
    setState((){busy=true;error=null;});
    try{
      final next=await service!.analyze(photos.map((p)=>p.png).toList(),Map.of(answers),plan);
      if(!mounted)return;
      setState((){plan=next;needsAnalysis=false;approved=false;stl=null;part=null;selected=null;});await persist();
    }catch(e){failure(e);}finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> answer(PhotoPartQuestion question)async{
    if(busy)return;
    final controller=TextEditingController(text:answers[question.id]?.toString().replaceAll('.',',')??'');String? problem;
    final route=DialogRoute<Object>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,refresh)=>AlertDialog(scrollable:true,
      title:Text(question.label),content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(question.help),const SizedBox(height:12),
        if(!question.isLength&&question.choices.isNotEmpty)...[for(final choice in question.choices)Padding(padding:const EdgeInsets.only(bottom:8),child:OutlinedButton(onPressed:()=>Navigator.pop(ctx,choice),child:Text(choice)))],
        if(question.isLength||question.choices.isEmpty)TextField(key:const ValueKey('photo-answer-input'),controller:controller,autofocus:true,maxLength:question.isLength?40:500,
          decoration:InputDecoration(labelText:question.isLength?'Maß in mm':'Deine Antwort',helperText:question.isLength?'Auch möglich: 6,8 cm':null,errorText:problem)),
      ]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Abbrechen')),
        if(question.isLength||question.choices.isEmpty)FilledButton(onPressed:(){
          final Object? result=question.isLength?photoLengthMillimetres(controller.text):controller.text.trim();
          if(result==null||result is String&&result.isEmpty){refresh(()=>problem=question.isLength?'Positives Maß in mm oder cm eingeben.':'Bitte eine Antwort eingeben.');return;}
          Navigator.pop(ctx,result);
        },child:const Text('Angabe bestätigen')),
      ],
    )));
    final value=await Navigator.of(context).push(route);await route.completed;controller.dispose();
    if(value==null||!mounted)return;
    setState((){answers[question.id]=value;needsAnalysis=true;approved=false;part=null;stl=null;selected=null;});
    try{await persist();}catch(e){failure(e);}
  }
  Future<void> generate()async{
    setState((){busy=true;error=null;});
    try{
      final bytes=await service!.generate(plan!,Map.of(answers),photos.length,approved);
      final model=await compute(photoPartFromStl,bytes);
      if(mounted)setState((){stl=bytes;part=model;});
    }catch(e){failure(e);}finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> saveStl()async{
    try{await FilePicker.platform.saveFile(dialogTitle:'Foto-Bauteil speichern',fileName:'Foto_Bauteil.stl',type:FileType.custom,allowedExtensions:['stl'],bytes:stl!);}
    catch(e){failure(e);}
  }
  Future<void> reset()async{
    final yes=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Neues Foto-Bauteil?'),content:const Text('Der aktuelle Fotoentwurf mit seinen Maßangaben wird entfernt. Bereits gespeicherte STL-Dateien und Druckprojekte bleiben erhalten.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Abbrechen')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Neuer Entwurf'))]));
    if(yes!=true||!mounted)return;
    setState((){busy=true;photos.clear();answers.clear();plan=null;part=null;stl=null;selected=null;approved=false;needsAnalysis=true;error=null;});
    try{await persist();if(directory!=null){await for(final file in directory!.list()){if(file is File&&file.path.endsWith('.png'))await file.delete();}}}catch(e){failure(e);}finally{if(mounted)setState(()=>busy=false);}
  }
  @override void dispose(){service?.cancel();super.dispose();}
  @override Widget build(BuildContext context){
    PhotoPartQuestion? current;
    if(plan!=null){current=plan!.questions.where((q)=>q.id==selected).firstOrNull??plan!.questions.where((q)=>!answers.containsKey(q.id)).firstOrNull;}
    final complete=plan!=null&&plan!.questions.every((q)=>answers.containsKey(q.id));
    final canGenerate=consent&&service!=null&&complete&&!needsAnalysis&&plan!.status=='ready'&&plan!.blockers.isEmpty&&(plan!.assumptions.isEmpty||approved);
    return Scaffold(appBar:AppBar(title:const Text('Fotos zu STL'),actions:[
      if(stl!=null)IconButton(tooltip:'STL speichern',onPressed:busy?null:saveStl,icon:const Icon(Icons.save_outlined)),
      IconButton(tooltip:'Neuer Fotoentwurf',onPressed:busy?null:reset,icon:const Icon(Icons.note_add_outlined)),
      if(part!=null)TextButton(onPressed:busy?null:()=>Navigator.pop(context,part),child:const Text('Übernehmen'))
      else TextButton(onPressed:busy||!canGenerate?null:generate,child:const Text('3D erzeugen')),
    ]),body:SafeArea(top:false,child:ListView(padding:const EdgeInsets.all(20),children:[
      const StudioHeading('Dein Teil als Druckmodell.',subtitle:'4–8 Ansichten aufnehmen, Maße klären, 3D prüfen.'),
      const Text('Vorne, hinten, links, rechts; bei Bedarf oben, unten und schräg. Dasselbe Bauteil gut beleuchtet aufnehmen.'),const SizedBox(height:12),
      Wrap(spacing:8,runSpacing:8,children:[
        OutlinedButton.icon(onPressed:busy||photos.length>=8?null:()=>addPhotos(true),icon:const Icon(Icons.photo_camera_outlined),label:const Text('Foto aufnehmen')),
        OutlinedButton.icon(onPressed:busy||photos.length>=8?null:()=>addPhotos(false),icon:const Icon(Icons.photo_library_outlined),label:const Text('Fotos laden')),
      ]),const SizedBox(height:12),Text('${photos.length} von 8 Fotos · mindestens 4'),
      if(photos.isNotEmpty)SizedBox(height:92,child:ListView(scrollDirection:Axis.horizontal,children:[for(var i=0;i<photos.length;i++)Padding(padding:const EdgeInsets.only(right:8),child:Column(children:[
        SizedBox(height:66,width:76,child:Image.memory(photos[i].png,fit:BoxFit.cover)),Text('Foto ${i+1}',style:const TextStyle(fontSize:11)),
      ]))])),
      CheckboxListTile(contentPadding:EdgeInsets.zero,title:const Text('Fotos zur Online-Auswertung senden'),subtitle:const Text('Erst beim Analysieren werden diese Fotos und bestätigte Angaben an den eingerichteten Fotodienst übermittelt.'),value:consent,onChanged:busy?null:(v)=>setState(()=>consent=v==true)),
      if(part==null)FilledButton.icon(onPressed:busy||photos.length<4||!consent?null:analyze,icon:const Icon(Icons.auto_awesome_outlined),label:Text(plan==null?'Bauteil analysieren':'Mit Angaben weiter auswerten')),
      if(busy)...[const SizedBox(height:12),const LinearProgressIndicator(),TextButton(onPressed:service?.cancel,child:const Text('Anfrage abbrechen'))],
      if(error!=null)Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
      if(plan!=null)...[
        const SizedBox(height:16),Text(plan!.name,style:const TextStyle(fontSize:21,fontWeight:FontWeight.w700)),Text(plan!.summary),
        for(final blocker in plan!.blockers)Padding(padding:const EdgeInsets.only(top:8),child:Text(blocker,style:TextStyle(color:Theme.of(context).colorScheme.error))),
        if(current!=null)...[
          const SizedBox(height:16),Text(current.label,style:const TextStyle(fontWeight:FontWeight.w700,fontSize:18)),Text(current.help),const SizedBox(height:10),
          if(current.imageIndex>=0)AnnotatedPhotoQuestion(photo:photos[current.imageIndex],question:current,value:answers[current.id],onTap:()=>answer(current!))
          else const Text('Die Messstelle ist auf den Fotos nicht sicher sichtbar. Bitte der Beschreibung folgen; bei Unklarheit eine zusätzliche Ansicht ergänzen.'),
          FilledButton(onPressed:busy?null:()=>answer(current!),child:const Text('Maß oder Antwort eintragen')),
        ],
        if(plan!.questions.isNotEmpty)...[const SizedBox(height:16),const Text('Bestätigte Angaben',style:TextStyle(fontWeight:FontWeight.w700)),
          for(final q in plan!.questions.where((q)=>answers.containsKey(q.id)))ListTile(contentPadding:EdgeInsets.zero,title:Text(q.label),subtitle:Text('${answers[q.id]}${q.isLength?' mm':''}'),trailing:IconButton(tooltip:'${q.label} ändern',onPressed:busy?null:(){setState(()=>selected=q.id);answer(q);},icon:const Icon(Icons.edit_outlined))),
        ],
        if(plan!.assumptions.isNotEmpty)...[
          const Text('Näherungen im Entwurf',style:TextStyle(fontWeight:FontWeight.w700)),for(final note in plan!.assumptions)Text('• $note'),
          CheckboxListTile(contentPadding:EdgeInsets.zero,title:const Text('Diese Näherungen für den Entwurf übernehmen'),value:approved,onChanged:busy?null:(v)=>setState(()=>approved=v==true)),
        ],
        if(complete&&needsAnalysis)const Text('Alle bisherigen Fragen sind beantwortet. Oben weiter auswerten; die Analyse kann noch weitere Maße benötigen.'),
      ],
      if(part!=null)...[
        const SizedBox(height:16),PhotoPartPreview(part:part!),
        Text('${part!.width.toStringAsFixed(1)} × ${part!.depth.toStringAsFixed(1)} × ${part!.height.toStringAsFixed(1)} mm'),
        const Text('Entwurf prüfen. Passungen mit einem kleinen Probedruck testen. Oben als STL speichern oder auf die Druckplatte übernehmen.'),
      ],
    ])));
  }
}

class AnnotatedPhotoQuestion extends StatelessWidget {
  const AnnotatedPhotoQuestion({super.key,required this.photo,required this.question,required this.onTap,this.value});
  final PhotoPartImage photo;final PhotoPartQuestion question;final Object? value;final VoidCallback onTap;
  @override Widget build(BuildContext context)=>InteractiveViewer(maxScale:5,child:AspectRatio(aspectRatio:photo.width/photo.height,child:LayoutBuilder(builder:(context,c){
    final center=Offset((question.a[0]+question.b[0])/2,(question.a[1]+question.b[1])/2);
    return Stack(fit:StackFit.expand,children:[Image.memory(photo.png,fit:BoxFit.fill),IgnorePointer(child:CustomPaint(painter:_PhotoDimension(question.a,question.b))),
      Positioned(left:(center.dx*c.maxWidth-68).clamp(0,math.max(0,c.maxWidth-136)).toDouble(),top:(center.dy*c.maxHeight-24).clamp(0,math.max(0,c.maxHeight-48)).toDouble(),width:136,
        child:FilledButton(key:ValueKey('photo-measure-${question.id}'),onPressed:onTap,child:Text(value==null?'Maß eintragen':'$value${question.isLength?' mm':''}',textAlign:TextAlign.center))),
    ]);
  })));
}
class _PhotoDimension extends CustomPainter{
  _PhotoDimension(this.a,this.b);final List<double> a,b;
  @override void paint(Canvas canvas,Size size){
    final start=Offset(a[0]*size.width,a[1]*size.height),end=Offset(b[0]*size.width,b[1]*size.height);
    canvas.drawLine(start,end,Paint()..color=Colors.white..strokeWidth=6);canvas.drawLine(start,end,Paint()..color=const Color(0xff6550c7)..strokeWidth=3);
    for(final p in [start,end]){canvas.drawCircle(p,7,Paint()..color=Colors.white);canvas.drawCircle(p,4,Paint()..color=const Color(0xff6550c7));}
  }
  @override bool shouldRepaint(_PhotoDimension old)=>!listEquals(a,old.a)||!listEquals(b,old.b);
}

class PhotoPartPreview extends StatefulWidget {
  const PhotoPartPreview({super.key,required this.part});final PlatePart part;
  @override State<PhotoPartPreview> createState()=>_PhotoPartPreviewState();
}
class _PhotoPartPreviewState extends State<PhotoPartPreview>{
  ui.Image? image;double x=25,y=30;int revision=0;bool rendering=false;
  @override void initState(){super.initState();render();}
  Future<void> render()async{
    revision++;if(rendering)return;rendering=true;
    try{while(mounted){final request=revision,pixels=await compute(renderMesh,MeshRenderRequest(widget.part.vertices,320,320,x,y,1));
      if(!mounted)return;final complete=Completer<ui.Image>();ui.decodeImageFromPixels(pixels,320,320,ui.PixelFormat.rgba8888,complete.complete);final next=await complete.future;
      if(!mounted||request!=revision){next.dispose();if(!mounted)return;continue;}final old=image;setState(()=>image=next);if(old!=null)WidgetsBinding.instance.addPostFrameCallback((_)=>old.dispose());break;
    }}finally{rendering=false;}
  }
  @override void didUpdateWidget(PhotoPartPreview old){super.didUpdateWidget(old);if(old.part!=widget.part)render();}
  @override void dispose(){image?.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>Container(height:300,color:const Color(0xff1c1a2d),child:GestureDetector(onPanUpdate:(d){x=(x+d.delta.dy).clamp(-180.0,180.0).toDouble();y=(y+d.delta.dx).clamp(-180.0,180.0).toDouble();render();},child:image==null?const Center(child:CircularProgressIndicator()):RawImage(image:image,fit:BoxFit.contain)));
}
