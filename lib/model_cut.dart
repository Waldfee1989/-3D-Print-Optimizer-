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
  const CutSettings(this.axis,this.fraction,this.pins,this.diameter,this.length,this.clearance);
  final int axis;
  final double fraction,diameter,length,clearance;
  final bool pins;
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
  final settings=await showDialog<CutSettings>(context: context,builder: (_)=>_CutDialog(part,scale,bed));
  if(settings==null || !context.mounted) return null;
  return Navigator.push<List<PlatePart>>(context,MaterialPageRoute(builder: (_)=>_CutProgressPage(part,scale,settings)));
}
class _CutDialog extends StatefulWidget {
  const _CutDialog(this.part,this.scale,this.bed);
  final PlatePart part;final double scale;final PrinterBed? bed;
  @override State<_CutDialog> createState()=>_CutDialogState();
}
class _CutDialogState extends State<_CutDialog> {
  final form=GlobalKey<FormState>();
  late int axis;
  double fraction=.5;bool pins=true;
  final diameter=TextEditingController(text:'4'),length=TextEditingController(text:'5'),clearance=TextEditingController(text:'0,2');
  @override void initState(){super.initState();final p=widget.part,b=widget.bed;
    final ratios=[p.width/(b?.width??1),p.depth/(b?.depth??1),p.height/(b?.height??1)];axis=ratios.indexOf(ratios.reduce(math.max));}
  double number(String text)=>double.parse(text.replaceAll(',','.'));
  @override void dispose(){diameter.dispose();length.dispose();clearance.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>AlertDialog(title:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
    const Text('Modell teilen'),FilledButton(onPressed:(){if(form.currentState!.validate())Navigator.pop(context,CutSettings(axis,fraction,pins,number(diameter.text),number(length.text),number(clearance.text)));},child:const Text('Teilen')),
  ]),content:SingleChildScrollView(child:Form(key:form,child:Column(mainAxisSize:MainAxisSize.min,children:[
    DropdownButtonFormField<int>(isExpanded: true,initialValue:axis,decoration:const InputDecoration(labelText:'Schnittachse'),items:[for(var i=0;i<3;i++)DropdownMenuItem(value:i,child:Text(['X · Breite','Y · Tiefe','Z · Höhe'][i]))],onChanged:(v)=>setState(()=>axis=v!)),
    Text('Schnittposition: ${(fraction*100).toStringAsFixed(0)} %'),Slider(value:fraction,min:.1,max:.9,divisions:80,onChanged:(v)=>setState(()=>fraction=v)),
    SwitchListTile(title:const Text('Zwei Zapfen mit Gegenlöchern'),value:pins,onChanged:(v)=>setState(()=>pins=v)),
    for(final field in [(diameter,'Zapfendurchmesser in mm',2.0,30.0),(length,'Zapfenlänge in mm',2.0,30.0),(clearance,'Spiel je Seite in mm',.05,1.0)]) Padding(padding:const EdgeInsets.only(bottom:12),child:TextFormField(
      controller:field.$1,decoration:InputDecoration(labelText:field.$2),keyboardType:const TextInputType.numberWithOptions(decimal:true),validator:(text){final n=double.tryParse((text??'').replaceAll(',','.'));return n==null||!n.isFinite||n<field.$3||n>field.$4?'Wert zwischen ${field.$3} und ${field.$4} eintragen.':null;})),
    const Text('Verbindungen brauchen ausreichend massives Material. Passung zuerst mit einem kleinen Probedruck prüfen. Originaldatei bleibt unverändert.'),
  ]))));
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
        'axis':s.axis,'fraction':s.fraction,'pins':s.pins,'diameter':s.diameter,'length':s.length,'clearance':s.clearance});
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
