import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'build_plate.dart';
import 'printer_setup.dart';

const cutChannel = MethodChannel('print_optimizer/model_cut');
class CutSettings {
  const CutSettings(this.axis,this.fraction,this.connection,this.diameter,this.length,this.clearance,[this.pitch=2]);
  final int axis,connection;
  final double fraction,diameter,length,clearance,pitch;
}
PlatePart normalizeCutPart((String,Float32List) input) {
  final v=input.$2;
  if (v.isEmpty || v.length%9!=0) throw const FormatException('Leeres Teilstück.');
  var minX=double.infinity,minY=double.infinity,minZ=double.infinity;
  var maxX=double.negativeInfinity,maxY=double.negativeInfinity,maxZ=double.negativeInfinity;
  for(var i=0;i<v.length;i+=3) {
    minX=math.min(minX,v[i]);maxX=math.max(maxX,v[i]);minY=math.min(minY,v[i+1]);maxY=math.max(maxY,v[i+1]);minZ=math.min(minZ,v[i+2]);maxZ=math.max(maxZ,v[i+2]);
  }
  final width=maxX-minX,depth=maxY-minY,height=maxZ-minZ;
  final radius=math.max(.001,math.sqrt(width*width+depth*depth+height*height)/2);
  if(!radius.isFinite) throw const FormatException('Ungültige Schnittgeometrie.');
  final out=Float32List(v.length);
  for(var i=0;i<v.length;i+=3) {out[i]=(v[i]-(minX+maxX)/2)/radius;out[i+1]=(v[i+1]-(minY+maxY)/2)/radius;out[i+2]=(v[i+2]-(minZ+maxZ)/2)/radius;}
  return PlatePart(name: input.$1,vertices: out,unitScale: radius,width: width,depth: depth,height: height);
}
Float32List rotatePlateForCut((Float32List,int) input) {
  final out=Float32List(input.$1.length);
  for(var i=0;i<out.length;i+=3) {
    final x=input.$1[i],y=input.$1[i+1];
    final p=switch(input.$2%4){1=>(-y,x),2=>(-x,-y),3=>(y,-x),_=>(x,y)};
    out[i]=p.$1;out[i+1]=p.$2;out[i+2]=input.$1[i+2];
  }
  return out;
}
Future<List<PlatePart>?> requestModelCut(BuildContext context,PlatePart part,double scale,{PrinterBed? bed}) async {
  if(!Platform.isAndroid) return null;
  final settings=await showDialog<CutSettings>(context: context,builder: (_)=>CutDialog(part,scale,bed));
  if(settings==null || !context.mounted) return null;
  return Navigator.push<List<PlatePart>>(context,MaterialPageRoute(builder: (_)=>_CutProgressPage(part,scale,settings)));
}
class CutDialog extends StatefulWidget {
  const CutDialog(this.part,this.scale,this.bed);
  final PlatePart part;final double scale;final PrinterBed? bed;
  @override State<CutDialog> createState()=>CutDialogState();
}
class CutDialogState extends State<CutDialog> {
  final form=GlobalKey<FormState>();
  late int axis;
  double fraction=.5;int connection=1;
  final diameter=TextEditingController(text:'4'),length=TextEditingController(text:'5'),clearance=TextEditingController(text:'0,2'),pitch=TextEditingController(text:'2');
  @override void initState(){super.initState();final p=widget.part,b=widget.bed;
    final ratios=[p.width/(b?.width??1),p.depth/(b?.depth??1),p.height/(b?.height??1)];axis=ratios.indexOf(ratios.reduce(math.max));}
  double number(String text)=>double.parse(text.replaceAll(',','.'));
  @override void dispose(){diameter.dispose();length.dispose();clearance.dispose();pitch.dispose();super.dispose();}
  void choose(int value) => setState(() {
    connection=value;
    diameter.text=value==2?'10':value==3?'6':'4';
    length.text=value==2?'8':value==3?'10':'5';
  });
  String? validateNumber(String? text,double min,double max) {
    final value=double.tryParse((text??'').replaceAll(',','.'));
    return value==null||!value.isFinite||value<min||value>max?'Erlaubt: $min bis $max mm.':null;
  }
  Widget field(TextEditingController controller,String label,double min,double max,{String? Function(String?)? extra}) => Padding(
    padding:const EdgeInsets.only(bottom:14),child:TextFormField(controller:controller,
      decoration:InputDecoration(labelText:label,suffixText:'mm'),keyboardType:const TextInputType.numberWithOptions(decimal:true),
      validator:(text)=>validateNumber(text,min,max)??extra?.call(text)));
  @override Widget build(BuildContext context)=>AlertDialog(
    title:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('Modell teilen'),const SizedBox(height:12),
      SizedBox(width:double.infinity,child:FilledButton.icon(icon:const Icon(Icons.content_cut),onPressed:(){
        if(form.currentState!.validate())Navigator.pop(context,CutSettings(axis,fraction,connection,
          connection==0?4:number(diameter.text),connection==0?5:number(length.text),connection==0?.2:number(clearance.text),connection==2?number(pitch.text):2));
      },label:const Text('Teilen'))),
    ]),
    content:SizedBox(width:420,child:SingleChildScrollView(child:Form(key:form,child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('Verbindung',style:TextStyle(fontWeight:FontWeight.w700)),const SizedBox(height:10),
      LayoutBuilder(builder:(context,c)=>Wrap(spacing:8,runSpacing:8,children:[for(var i=0;i<4;i++)SizedBox(
        width:(c.maxWidth-8)/2,child:InkWell(borderRadius:BorderRadius.circular(16),onTap:()=>choose(i),
          child:AnimatedContainer(duration:const Duration(milliseconds:160),padding:const EdgeInsets.all(12),
            decoration:BoxDecoration(borderRadius:BorderRadius.circular(16),
              color:connection==i?Theme.of(context).colorScheme.primaryContainer:Theme.of(context).colorScheme.surfaceContainerLow,
              border:Border.all(color:connection==i?Theme.of(context).colorScheme.primary:Theme.of(context).colorScheme.outlineVariant)),
            child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Row(children:[Icon([Icons.cut,Icons.align_vertical_bottom,Icons.hardware_outlined,Icons.link][i],size:23),const Spacer(),
                if(connection==i)Icon(Icons.check_circle,size:18,color:Theme.of(context).colorScheme.primary)]),
              const SizedBox(height:8),Text(['Ohne Verbindung','Zapfen','Schraubgewinde','Klickverschluss'][i],style:const TextStyle(fontSize:13,fontWeight:FontWeight.w700)),
            ]))))])),
      const SizedBox(height:14),
      Text(switch(connection){2=>'Ein Gewinde mit passender Aufnahme. Die Teile müssen sich beim Zusammenschrauben drehen können.',
        3=>'Zwei geschlitzte Rastzapfen mit Haltekante. Elastizität und Passung zuerst am Probedruck prüfen.',
        1=>'Zwei Zapfen mit passenden Gegenlöchern.',_=>'Nur teilen und Schnittflächen schließen.'}),
      const SizedBox(height:20),
      DropdownButtonFormField<int>(isExpanded:true,initialValue:axis,decoration:const InputDecoration(labelText:'Schnittachse'),
        items:[for(var i=0;i<3;i++)DropdownMenuItem(value:i,child:Text(['X · Breite','Y · Tiefe','Z · Höhe'][i]))],onChanged:(v)=>setState(()=>axis=v!)),
      const SizedBox(height:12),Text('Schnittposition: ${(fraction*100).toStringAsFixed(0)} %'),
      Slider(value:fraction,min:.1,max:.9,divisions:80,onChanged:(v)=>setState(()=>fraction=v)),
      if(connection!=0)...[
        field(diameter,'Durchmesser',connection==2?8:connection==3?4:2,30),
        field(length,'Länge',connection==3?6:2,30,extra:(text){
          final value=number(text!);
          final step=double.tryParse(pitch.text.replaceAll(',','.'));
          final d=double.tryParse(diameter.text.replaceAll(',','.'));
          if(connection==2&&step!=null&&value<3*step)return 'Mindestens drei Gewindesteigungen lang.';
          if(connection==3&&d!=null&&value<1.2*d)return 'Mindestens 1,2 × Durchmesser lang.';
          return null;
        }),
        if(connection==2)field(pitch,'Gewindesteigung',1,4),
        field(clearance,'Spiel je Seite',.05,1),
        const Text('Braucht ausreichend massives Material. Beide Teile gleich skalieren. Passung und Halt mit einem kleinen Probedruck prüfen.',style:TextStyle(fontSize:12)),
      ],
    ])))));
}

class _CutProgressPage extends StatefulWidget {
  const _CutProgressPage(this.part,this.scale,this.settings);
  final PlatePart part;final double scale;final CutSettings settings;
  @override State<_CutProgressPage> createState()=>_CutProgressPageState();
}
class _CutProgressPageState extends State<_CutProgressPage> {
  String? error;
  @override void initState(){super.initState();run();}
  Future<void> run() async {
    try {
      final s=widget.settings;
      final result=await cutChannel.invokeMethod<List<dynamic>>('cut',{'vertices':widget.part.vertices,'scale':widget.part.unitScale*widget.scale,
        'axis':s.axis,'fraction':s.fraction,'connection':s.connection,'diameter':s.diameter,'length':s.length,'clearance':s.clearance,'pitch':s.pitch});
      if(result==null||result.length!=2)throw const FormatException('Schnitt lieferte keine zwei Teile.');
      final parts=<PlatePart>[];
      for(var i=0;i<2;i++) {
        final raw=result[i];final vertices=raw is Float32List?raw:Float32List.fromList((raw as List).map((n)=>(n as num).toDouble()).toList());
        parts.add(await compute(normalizeCutPart,('${widget.part.name} · Teil ${i+1}',vertices)));
      }
      if(mounted)Navigator.pop(context,parts);
    } catch(e){if(mounted)setState(()=>error=e is PlatformException?e.message??'Schnitt fehlgeschlagen.':'Schnitt konnte nicht berechnet werden.');}
  }
  @override Widget build(BuildContext context)=>PopScope(canPop:error!=null,child:Scaffold(appBar:AppBar(title:const Text('Modell wird geteilt'),automaticallyImplyLeading:error!=null),
    body:Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[
      if(error==null)...[const CircularProgressIndicator(),const SizedBox(height:20),const Text('Schnittflächen und Verbindungen werden lokal berechnet …')]
      else...[Text(error!),const SizedBox(height:16),FilledButton(onPressed:()=>Navigator.pop(context),child:const Text('Zurück'))],
    ])))));
}
