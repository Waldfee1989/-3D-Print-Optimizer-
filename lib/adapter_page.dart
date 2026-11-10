import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'adapter_geometry.dart';
import 'adapter_request.dart';
import 'adapter_measure_sketch.dart';
import 'app_design.dart';
import 'build_plate.dart';
import 'component_geometry.dart';
import 'component_page.dart';
import 'component_preview.dart';

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
  ComponentShape shape=ComponentShape.adapter;
  DiameterKind? kind;PlatePart? created;
  String? error,transcript;bool busy=false;
  Future<void> editSketchField(AdapterField field)async{
    final port=field==AdapterField.first?draft.first:field==AdapterField.second?draft.second:null;
    final initial=switch(field){
      AdapterField.first||AdapterField.second=>port?.diameter,
      AdapterField.length=>draft.length,AdapterField.wall=>draft.wall,AdapterField.socket=>draft.socket,
    };
    final entry=await showDialog<_MeasuredValue>(context:context,builder:(_)=>_DimensionEntryDialog(field:field,initial:initial,kind:port?.kind));
    if(entry==null||!mounted)return;
    setState((){
      switch(field){
        case AdapterField.first:draft.first=AdapterPort(entry.kind!,entry.value);
        case AdapterField.second:draft.second=AdapterPort(entry.kind!,entry.value);
        case AdapterField.length:draft.length=entry.value;
        case AdapterField.wall:draft.wall=entry.value;
        case AdapterField.socket:draft.socket=entry.value;
      }
      created=null;error=null;
    });
  }
  Future<void> openSketch()async{
    await showDialog<void>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,refresh)=>Dialog(
      insetPadding:const EdgeInsets.symmetric(horizontal:12,vertical:20),
      child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:600),child:SingleChildScrollView(padding:const EdgeInsets.all(16),child:Column(mainAxisSize:MainAxisSize.min,children:[
        Row(children:[const Expanded(child:Text('Maße am Bauteil',style:TextStyle(fontSize:20,fontWeight:FontWeight.w700))),IconButton(tooltip:'Skizze schließen',onPressed:()=>Navigator.pop(ctx),icon:const Icon(Icons.close))]),
        AdapterMeasureSketch(draft:draft,onEdit:(field)async{await editSketchField(field);if(ctx.mounted)refresh((){});}),
        if(draft.complete&&draft.spec().validate()!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(draft.spec().validate()!,style:TextStyle(color:Theme.of(ctx).colorScheme.error))),
      ]))),
    )));
  }
  void apply(String text){
    setState((){
      error=draft.answer(text,kind:kind)?null:'Angabe nicht erkannt. Bitte die Größe und bei Durchmessern innen oder außen angeben.';
      if(error==null){answer.clear();kind=null;created=null;}
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
  Widget shapeChooser()=>DropdownButtonFormField<ComponentShape>(
    key:ValueKey(shape),initialValue:shape,isExpanded:true,
    decoration:const InputDecoration(labelText:'Welche Form hat dein Bauteil?'),
    items:[for(final value in ComponentShape.values)DropdownMenuItem(value:value,child:Text(value.label,overflow:TextOverflow.ellipsis))],
    onChanged:busy?null:(value){if(value!=null)setState((){shape=value;created=null;error=null;});},
  );
  @override Widget build(BuildContext context){
    if(shape!=ComponentShape.adapter)return ComponentBuilderPage(key:ValueKey(shape),shape:shape,chooser:shapeChooser());
    final invalid=draft.complete?draft.spec().validate():null;
    String mm(double value)=>'${value.toStringAsFixed(2).replaceAll(RegExp(r'0+$'),'').replaceAll(RegExp(r'\.$'),'')} mm';
    final rows=<(AdapterField,String,String)>[
      if(draft.first!=null)(AdapterField.first,'Seite A','${draft.first!.kind==DiameterKind.inner?'Innen':'Außen'}durchmesser ${mm(draft.first!.diameter)}'),
      if(draft.second!=null)(AdapterField.second,'Seite B','${draft.second!.kind==DiameterKind.inner?'Innen':'Außen'}durchmesser ${mm(draft.second!.diameter)}'),
      if(draft.length!=null)(AdapterField.length,'Gesamtlänge',mm(draft.length!)),
      if(draft.wall!=null)(AdapterField.wall,'Wandstärke an den Öffnungen',mm(draft.wall!)),
      if(draft.socket!=null)(AdapterField.socket,'Steckbereich je Seite',mm(draft.socket!)),
    ];
    return Scaffold(appBar:AppBar(title:const Text('Bauteil erstellen'),actions:[
      TextButton(onPressed:busy||!draft.complete||invalid!=null?null:created==null?create:()=>Navigator.pop(context,created),child:Text(created==null?'Erstellen':'Übernehmen')),
    ]),body:SafeArea(top:false,child:ListView(padding:const EdgeInsets.all(20),children:[
      shapeChooser(),const SizedBox(height:20),
      const StudioHeading('Beschreiben. Prüfen. Erstellen.',subtitle:'Runder Übergang mit zwei Steckseiten. Für andere Bauteile oben die Form wählen.'),
      OutlinedButton.icon(onPressed:busy?null:openSketch,icon:const Icon(Icons.design_services_outlined),label:const Text('Maß in Skizze eintragen')),
      const SizedBox(height:12),
      if(created!=null)...[
        ComponentPreview(part:created!),const SizedBox(height:12),
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
      if(invalid!=null)Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text(invalid,style:TextStyle(color:Theme.of(context).colorScheme.error))),
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
class _MeasuredValue {
  const _MeasuredValue(this.value,this.kind);
  final double value;final DiameterKind? kind;
}
class _DimensionEntryDialog extends StatefulWidget {
  const _DimensionEntryDialog({required this.field,this.initial,this.kind});
  final AdapterField field;final double? initial;final DiameterKind? kind;
  @override State<_DimensionEntryDialog> createState()=>_DimensionEntryDialogState();
}
class _DimensionEntryDialogState extends State<_DimensionEntryDialog>{
  late final controller=TextEditingController(text:widget.initial?.toString().replaceAll('.',',')??'');
  late DiameterKind? kind=widget.kind;
  String? error;
  bool get isPort=>widget.field==AdapterField.first||widget.field==AdapterField.second;
  void save(){
    final match=RegExp(r'^(\d+(?:[.,]\d+)?)\s*(mm|cm)?$',caseSensitive:false).firstMatch(controller.text.trim());
    final value=match==null?null:double.tryParse(match[1]!.replaceAll(',','.'));
    final millimetres=value==null?null:value*(match![2]?.toLowerCase()=='cm'?10:1);
    if(millimetres==null||!millimetres.isFinite||millimetres<=0){setState(()=>error='Ein positives Maß in mm oder cm eintragen.');return;}
    if(isPort&&kind==null){setState(()=>error='Bitte ausdrücklich Innenmaß oder Außenmaß wählen.');return;}
    final range=switch(widget.field){
      AdapterField.first||AdapterField.second=>(2.0,1000.0),
      AdapterField.length=>(5.0,2000.0),AdapterField.wall=>(.8,30.0),AdapterField.socket=>(2.0,500.0),
    };
    if(millimetres<range.$1||millimetres>range.$2){setState(()=>error='Maß zwischen ${AdapterMeasureSketch.millimetres(range.$1)} und ${AdapterMeasureSketch.millimetres(range.$2)} eintragen.');return;}
    Navigator.pop(context,_MeasuredValue(millimetres,kind));
  }
  @override void dispose(){controller.dispose();super.dispose();}
  @override Widget build(BuildContext context){
    final title=switch(widget.field){AdapterField.first=>'Durchmesser Seite A',AdapterField.second=>'Durchmesser Seite B',AdapterField.length=>'Gesamtlänge',AdapterField.wall=>'Wandstärke',AdapterField.socket=>'Steckbereich je Seite'};
    final hint=switch(widget.field){
      AdapterField.first||AdapterField.second=>'Innen: freie Öffnung. Außen: von Außenkante zu Außenkante einschließlich Wand.',
      AdapterField.length=>'Von Stirnfläche A bis Stirnfläche B, einschließlich beider gerader Steckbereiche.',
      AdapterField.wall=>'Nur das feste Material zwischen Innenfläche und Außenfläche an einer Öffnung messen.',
      AdapterField.socket=>'Länge eines geraden Endstücks bis zum Beginn der Schräge. Die Vorlage verwendet an beiden Seiten die gleiche Länge.',
    };
    return AlertDialog(scrollable:true,title:Text(title),content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(hint),const SizedBox(height:16),
      if(isPort)Wrap(spacing:8,children:[
        ChoiceChip(label:const Text('Innenmaß'),selected:kind==DiameterKind.inner,onSelected:(_)=>setState(()=>kind=DiameterKind.inner)),
        ChoiceChip(label:const Text('Außenmaß'),selected:kind==DiameterKind.outer,onSelected:(_)=>setState(()=>kind=DiameterKind.outer)),
      ]),
      const SizedBox(height:8),TextField(key:const ValueKey('sketch-dimension-input'),controller:controller,autofocus:true,
        decoration:InputDecoration(labelText:'Maß in mm',helperText:'Auch möglich: 6,8 cm',errorText:error),
        keyboardType:TextInputType.text,textInputAction:TextInputAction.done,onSubmitted:(_)=>save()),
    ]),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Abbrechen')),FilledButton(onPressed:save,child:const Text('Maß speichern'))]);
  }
}
