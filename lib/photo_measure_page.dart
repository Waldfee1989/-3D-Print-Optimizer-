import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'adapter_geometry.dart';
import 'adapter_request.dart';
import 'app_design.dart';
import 'photo_measurement.dart';

class PhotoInput {
  const PhotoInput(this.image,this.pixels,this.name);
  final ui.Image image;final Uint8List pixels;final String name;
}
Future<PhotoInput?> chooseMeasurementPhoto()async{
  final result=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['png','jpg','jpeg','webp'],withData:false);
  if(result==null)return null;final file=result.files.single;
  const limit=25*1024*1024;
  if(file.size>limit||(file.path!=null&&await File(file.path!).length()>limit))throw const FormatException('Foto ist größer als 25 MB.');
  final bytes=file.bytes??(file.path==null?null:await File(file.path!).readAsBytes());
  if(bytes==null||bytes.length>limit)throw const FormatException('Foto konnte nicht geladen werden.');
  final buffer=await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;ui.Codec? codec;ui.Image? image;
  try{
    descriptor=await ui.ImageDescriptor.encoded(buffer);
    if(descriptor.width<8||descriptor.height<8||descriptor.width*descriptor.height>80000000)throw const FormatException('Bildauflösung nicht unterstützt.');
    final factor=math.min(1,1200/math.max(descriptor.width,descriptor.height));
    codec=await descriptor.instantiateCodec(targetWidth:math.max(1,(descriptor.width*factor).round()),targetHeight:math.max(1,(descriptor.height*factor).round()));
    image=(await codec.getNextFrame()).image;
    final pixels=await image.toByteData(format:ui.ImageByteFormat.rawRgba);
    if(pixels==null)throw const FormatException('Bilddaten konnten nicht gelesen werden.');
    return PhotoInput(image,pixels.buffer.asUint8List(pixels.offsetInBytes,pixels.lengthInBytes),file.name);
  }catch(_){image?.dispose();rethrow;}
  finally{codec?.dispose();descriptor?.dispose();buffer.dispose();}
}
class PhotoMeasurePage extends StatefulWidget {
  const PhotoMeasurePage({super.key,this.choose});
  final Future<PhotoInput?> Function()? choose;
  @override State<PhotoMeasurePage> createState()=>_PhotoMeasurePageState();
}
class _PhotoMeasurePageState extends State<PhotoMeasurePage>{
  PhotoInput? photo;
  final reference=<PhotoPoint>[],measurement=<PhotoPoint>[];
  final known=TextEditingController();
  final draft=AdapterDraft();
  PhotoCalibration? calibration;
  bool busy=false,edges=true;String? error;
  double? get distance=>calibration!=null&&measurement.length==2?calibration!.measure(measurement[0],measurement[1]):null;
  String mm(double value)=>value.toStringAsFixed(2).replaceAll(RegExp(r'0+$'),'').replaceAll(RegExp(r'\.$'),'').replaceAll('.',',');
  String estimate(double value)=>value.toStringAsFixed(1).replaceAll('.',',');
  Future<void> pick()async{
    setState((){busy=true;error=null;});
    try{
      final value=await(widget.choose?.call()??chooseMeasurementPhoto());if(value==null)return;
      if(!mounted){value.image.dispose();return;}
      final old=photo;
      setState((){photo=value;reference.clear();measurement.clear();known.clear();calibration=null;draft.first=null;draft.second=null;});
      if(old!=null)WidgetsBinding.instance.addPostFrameCallback((_)=>old.image.dispose());
    }catch(e){if(mounted)setState(()=>error=e is FormatException?e.message:'Foto konnte nicht geöffnet werden. Bitte PNG, JPG oder WebP verwenden.');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  void tap(PhotoPoint point){
    final p=photo!;
    if(edges)point=snapPhotoEdge(p.pixels,p.image.width,p.image.height,point);
    setState((){
      error=null;
      if(calibration==null){if(reference.length==2)reference.clear();reference.add(point);}
      else{if(measurement.length==2)measurement.clear();measurement.add(point);}
    });
  }
  void calibrate(){
    final value=double.tryParse(known.text.replaceAll(',','.'));
    if(reference.length!=2||value==null){setState(()=>error='Zwei Referenzpunkte markieren und das bekannte Maß in mm eintragen.');return;}
    try{final next=PhotoCalibration(reference[0],reference[1],value);setState((){calibration=next;measurement.clear();draft.first=null;draft.second=null;error=null;});}
    on FormatException catch(e){setState(()=>error=e.message);}
  }
  Future<void> assign(double value,{bool estimated=false})async{
    final chosen=await showDialog<int>(context:context,builder:(ctx)=>SimpleDialog(title:Text('${estimated?estimate(value):mm(value)} mm übernehmen'),children:[
      for(var i=0;i<4;i++)SimpleDialogOption(onPressed:()=>Navigator.pop(ctx,i),child:Text('Seite ${i<2?'A':'B'} · ${i.isEven?'innen':'außen'}')),
    ]));
    if(chosen==null||!mounted)return;
    setState((){final port=AdapterPort(chosen.isEven?DiameterKind.inner:DiameterKind.outer,estimated?double.parse(value.toStringAsFixed(1)):value);
      if(chosen<2){draft.first=port;}else{draft.second=port;}});
  }
  @override void dispose(){known.dispose();photo?.image.dispose();super.dispose();}
  @override Widget build(BuildContext context){
    final p=photo,value=distance;
    final question=calibration==null?(reference.length==2?'Wie lang ist die markierte Referenz in Millimetern?':'Markiere zwei Endpunkte einer bekannten Strecke.'):
      measurement.length<2?'Markiere jetzt zwei Endpunkte der zu messenden Strecke.':'Die Bildschätzung ist berechnet.';
    return Scaffold(appBar:AppBar(title:const Text('Fotomaße'),actions:[
      TextButton(onPressed:draft.first==null&&draft.second==null?null:()=>Navigator.pop(context,draft),child:const Text('Zum Bauteil')),
    ]),body:SafeArea(top:false,child:ListView(padding:const EdgeInsets.all(20),children:[
      const StudioHeading('Ein Foto. Ein bekanntes Maß.',subtitle:'Weitere sichtbare Strecken im Bild schätzen.'),
      FilledButton.icon(onPressed:busy?null:pick,icon:const Icon(Icons.add_photo_alternate_outlined),label:const Text('Foto öffnen')),
      if(busy)const LinearProgressIndicator(),
      if(error!=null)Padding(padding:const EdgeInsets.all(12),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
      if(p!=null)...[
        const SizedBox(height:16),Text(question,style:const TextStyle(fontSize:17,fontWeight:FontWeight.w700)),const SizedBox(height:12),
        ClipRRect(borderRadius:BorderRadius.circular(20),child:Container(height:320,color:const Color(0xff211f34),child:InteractiveViewer(minScale:1,maxScale:8,
          child:Center(child:AspectRatio(aspectRatio:p.image.width/p.image.height,child:LayoutBuilder(builder:(context,c)=>GestureDetector(
            key:const ValueKey('photo-canvas'),behavior:HitTestBehavior.opaque,
            onTapUp:(event)=>tap(PhotoPoint((event.localPosition.dx/c.maxWidth*p.image.width).clamp(0,p.image.width-1).toDouble(),
              (event.localPosition.dy/c.maxHeight*p.image.height).clamp(0,p.image.height-1).toDouble())),
            child:Stack(fit:StackFit.expand,children:[RawImage(image:p.image,fit:BoxFit.fill),IgnorePointer(child:CustomPaint(
              painter:_PhotoMarks(p.image.width,p.image.height,List.of(reference),List.of(measurement))))]),
          ))))))),
        SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Kantenhilfe für neue Markierungen'),value:edges,onChanged:(v)=>setState(()=>edges=v)),
        if(calibration==null)...[
          TextField(controller:known,decoration:const InputDecoration(labelText:'Bekanntes Referenzmaß',suffixText:'mm'),keyboardType:const TextInputType.numberWithOptions(decimal:true)),
          const SizedBox(height:10),FilledButton(onPressed:reference.length==2?calibrate:null,child:const Text('Referenz übernehmen')),
        ]else...[
          Text('Referenz: ${mm(calibration!.millimetres)} mm',style:const TextStyle(fontWeight:FontWeight.w600)),
          Wrap(spacing:8,runSpacing:8,children:[
            TextButton(onPressed:()=>setState((){reference.clear();measurement.clear();calibration=null;draft.first=null;draft.second=null;}),child:const Text('Referenz neu setzen')),
            OutlinedButton(onPressed:()=>assign(calibration!.millimetres),child:const Text('Referenz für Bauteil')),
          ]),
        ],
        if(value!=null)Card(child:Padding(padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          const Text('BILDSCHÄTZUNG',style:TextStyle(fontSize:11,color:studioMuted,letterSpacing:1.2)),
          Text('${estimate(value)} mm',style:const TextStyle(fontSize:34,fontWeight:FontWeight.w800)),const SizedBox(height:12),
          Wrap(spacing:8,runSpacing:8,children:[
            FilledButton(onPressed:()=>assign(value,estimated:true),child:const Text('Messung für Bauteil')),
            IconButton(tooltip:'Messwert kopieren',onPressed:()=>Clipboard.setData(ClipboardData(text:'${estimate(value)} mm')),icon:const Icon(Icons.copy_outlined)),
          ]),
        ]))),
        if(draft.first!=null||draft.second!=null)Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          const Text('Für das Bauteil vorgemerkt',style:TextStyle(fontWeight:FontWeight.w700)),const SizedBox(height:8),
          if(draft.first!=null)Text('Seite A: ${draft.first!.kind==DiameterKind.inner?'innen':'außen'} ${mm(draft.first!.diameter)} mm'),
          if(draft.second!=null)Text('Seite B: ${draft.second!.kind==DiameterKind.inner?'innen':'außen'} ${mm(draft.second!.diameter)} mm'),
          const SizedBox(height:8),const Text('Oben „Zum Bauteil“ übernimmt diese Maße und fragt fehlende Angaben ab.',style:TextStyle(fontSize:12)),
        ]))),
      ],
      const SizedBox(height:18),const Text('Frontal fotografieren. Referenz und Messstrecke müssen in derselben Ebene liegen. Perspektive und Linsenverzerrung können das Ergebnis verändern; Passmaße nachmessen.',style:TextStyle(fontSize:12,color:studioMuted)),
    ])));
  }
}
class _PhotoMarks extends CustomPainter{
  const _PhotoMarks(this.width,this.height,this.reference,this.measurement);
  final int width,height;final List<PhotoPoint> reference,measurement;
  @override void paint(Canvas canvas,Size size){
    for(final entry in [(reference,studioPurple,'R'),(measurement,const Color(0xfff57c45),'M')]){
      final points=entry.$1.map((p)=>Offset(p.x/width*size.width,p.y/height*size.height)).toList();
      if(points.length==2){canvas.drawLine(points[0],points[1],Paint()..color=Colors.white..strokeWidth=5);canvas.drawLine(points[0],points[1],Paint()..color=entry.$2..strokeWidth=3);}
      for(var i=0;i<points.length;i++){
        canvas.drawCircle(points[i],7,Paint()..color=Colors.white);canvas.drawCircle(points[i],5,Paint()..color=entry.$2);
        final text=TextPainter(text:TextSpan(text:'${entry.$3}${i+1}',style:TextStyle(color:entry.$2,fontSize:12,fontWeight:FontWeight.bold,backgroundColor:Colors.white)),textDirection:TextDirection.ltr)..layout();
        text.paint(canvas,points[i]+const Offset(9,-18));
      }
    }
  }
  @override bool shouldRepaint(_PhotoMarks old)=>true;
}
