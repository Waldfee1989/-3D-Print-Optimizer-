import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'adapter_geometry.dart';
import 'adapter_request.dart';
import 'app_design.dart';
import 'build_plate.dart';
import 'mesh_renderer.dart';

const voiceChannel=MethodChannel('print_optimizer/voice');
class AdapterPage extends StatefulWidget {
  const AdapterPage({super.key,this.recognize,this.initialDraft});
  final Future<String?> Function()? recognize;
  final AdapterDraft? initialDraft;
  @override State<AdapterPage> createState()=>_AdapterPageState();
}
class _AdapterPageState extends State<AdapterPage>{
  late final draft=widget.initialDraft??AdapterDraft();
  final answer=TextEditingController();
  DiameterKind? kind;PlatePart? created;
  String? error,transcript;bool busy=false;
  void apply(String text){
    setState((){
      error=draft.answer(text,kind:kind)?null:'Angabe nicht erkannt. Bitte die Größe und bei Durchmessern innen oder außen angeben.';
      if(error==null){answer.clear();kind=null;}
    });
  }
  Future<void> speak()async{
    setState((){busy=true;error=null;});
    try{
      final text=await(widget.recognize?.call()??voiceChannel.invokeMethod<String>('recognize'));
      if(text!=null&&mounted){setState(()=>transcript=text);apply(text);}
    }catch(_){if(mounted)setState(()=>error='Die Android-Spracherkennung ist nicht verfügbar. Du kannst alle Angaben hier eintippen.');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> create()async{
    final spec=draft.spec();final invalid=spec.validate();
    if(invalid!=null){setState(()=>error=invalid);return;}
    setState((){busy=true;error=null;});
    try{final model=await compute(buildAdapter,spec);if(mounted)setState(()=>created=model);}
    catch(_){if(mounted)setState(()=>error='Bauteil konnte mit diesen Maßen nicht erzeugt werden.');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override void dispose(){answer.dispose();super.dispose();}
  @override Widget build(BuildContext context){
    String mm(double value)=>'${value.toStringAsFixed(2).replaceAll(RegExp(r'0+$'),'').replaceAll(RegExp(r'\.$'),'')} mm';
    final rows=<(AdapterField,String,String)>[
      if(draft.first!=null)(AdapterField.first,'Seite A','${draft.first!.kind==DiameterKind.inner?'Innen':'Außen'}durchmesser ${mm(draft.first!.diameter)}'),
      if(draft.second!=null)(AdapterField.second,'Seite B','${draft.second!.kind==DiameterKind.inner?'Innen':'Außen'}durchmesser ${mm(draft.second!.diameter)}'),
      if(draft.length!=null)(AdapterField.length,'Gesamtlänge',mm(draft.length!)),
      if(draft.wall!=null)(AdapterField.wall,'Wandstärke an den Öffnungen',mm(draft.wall!)),
      if(draft.socket!=null)(AdapterField.socket,'Steckbereich je Seite',mm(draft.socket!)),
    ];
    return Scaffold(appBar:AppBar(title:const Text('Bauteil erstellen'),actions:[
      TextButton(onPressed:busy||!draft.complete?null:created==null?create:()=>Navigator.pop(context,created),child:Text(created==null?'Erstellen':'Übernehmen')),
    ]),body:SafeArea(top:false,child:ListView(padding:const EdgeInsets.all(20),children:[
      const StudioHeading('Beschreiben. Prüfen. Erstellen.',subtitle:'Vorlage: Runder Übergang mit zwei Steckseiten.'),
      if(created!=null)...[
        _AdapterPreview(part:created!),const SizedBox(height:12),
        Text('Modell: ${created!.width.toStringAsFixed(1)} × ${created!.depth.toStringAsFixed(1)} × ${created!.height.toStringAsFixed(1)} mm'),
        TextButton(onPressed:()=>setState(()=>created=null),child:const Text('Maße ändern')),
      ]else...[
        Card(child:Padding(padding:const EdgeInsets.all(20),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Icon(draft.complete?Icons.fact_check_outlined:Icons.question_answer_outlined,color:studioPurple),const SizedBox(height:12),
          Text(draft.question,style:const TextStyle(fontSize:19,fontWeight:FontWeight.w700)),
          if(!draft.complete)...[
            const SizedBox(height:16),
            if(draft.next==AdapterField.first||draft.next==AdapterField.second)Wrap(spacing:8,children:[
              ChoiceChip(label:const Text('Innenmaß'),selected:kind==DiameterKind.inner,onSelected:(_)=>setState(()=>kind=DiameterKind.inner)),
              ChoiceChip(label:const Text('Außenmaß'),selected:kind==DiameterKind.outer,onSelected:(_)=>setState(()=>kind=DiameterKind.outer)),
            ]),
            const SizedBox(height:12),TextField(controller:answer,maxLength:1500,maxLines:3,minLines:1,
              decoration:const InputDecoration(labelText:'Deine Angabe',hintText:'Zum Beispiel: innen 35 mm und außen 50 mm',counterText:''),
              onSubmitted:busy?null:apply),
            const SizedBox(height:14),Wrap(spacing:8,runSpacing:8,children:[
              FilledButton(onPressed:busy?null:()=>apply(answer.text),child:const Text('Angabe übernehmen')),
              OutlinedButton.icon(onPressed:busy||(!Platform.isAndroid&&widget.recognize==null)?null:speak,
                icon:const Icon(Icons.mic_none),label:const Text('Sprechen')),
            ]),
            const SizedBox(height:12),const Text('Android übernimmt die Spracheingabe. Je nach Anbieter ist Internet nötig. Texteingabe geht immer.',style:TextStyle(fontSize:11,color:studioMuted)),
          ]else...[
            const SizedBox(height:12),const Text('Bitte alle Maße prüfen. Oben „Erstellen“ erzeugt das Modell.'),
          ],
        ]))),
      ],
      if(busy)const LinearProgressIndicator(),
      if(error!=null)Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
      if(transcript!=null)Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text('Erkannt: $transcript',style:const TextStyle(fontSize:12,color:studioMuted))),
      if(rows.isNotEmpty)...[
        const StudioHeading('Deine Maße'),
        Card(child:Column(children:[for(final row in rows)ListTile(title:Text(row.$2),subtitle:Text(row.$3),
          trailing:IconButton(tooltip:'${row.$2} ändern',icon:const Icon(Icons.edit_outlined),onPressed:busy?null:()=>setState((){draft.clear(row.$1);created=null;kind=null;error=null;}))),
        ])),
      ],
      const SizedBox(height:12),const Text('Keine Maße werden stillschweigend ergänzt. Angaben sind Nennmaße; die Steckpassung mit einem kleinen Probedruck prüfen.',style:TextStyle(fontSize:12)),
    ])));
  }
}
class _AdapterPreview extends StatefulWidget {
  const _AdapterPreview({required this.part});final PlatePart part;
  @override State<_AdapterPreview> createState()=>_AdapterPreviewState();
}
class _AdapterPreviewState extends State<_AdapterPreview>{
  ui.Image? image;double x=25,y=30;int revision=0;bool rendering=false;
  @override void initState(){super.initState();render();}
  Future<void> render()async{
    revision++;if(rendering)return;rendering=true;
    try{while(mounted){
      final request=revision,pixels=await compute(renderMesh,MeshRenderRequest(widget.part.vertices,300,300,x,y,1));
      if(!mounted)return;
      final complete=Completer<ui.Image>();ui.decodeImageFromPixels(pixels,300,300,ui.PixelFormat.rgba8888,complete.complete);
      final next=await complete.future;
      if(!mounted||request!=revision){next.dispose();if(!mounted)return;continue;}
      final old=image;setState(()=>image=next);if(old!=null)WidgetsBinding.instance.addPostFrameCallback((_)=>old.dispose());break;
    }}finally{rendering=false;}
  }
  @override void dispose(){image?.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>ClipRRect(borderRadius:BorderRadius.circular(24),child:Container(height:280,color:const Color(0xff1c1a2d),
    child:RawGestureDetector(gestures:{EagerGestureRecognizer:GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(()=>EagerGestureRecognizer(),(_){})},
      child:Listener(behavior:HitTestBehavior.opaque,onPointerMove:(event){x=(x+event.delta.dy).clamp(-180.0,180.0).toDouble();y=(y+event.delta.dx).clamp(-180.0,180.0).toDouble();render();},
        child:image==null?const Center(child:CircularProgressIndicator()):RawImage(image:image,fit:BoxFit.contain)))));
}
