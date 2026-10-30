import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'mesh_renderer.dart';
import 'model_size_dialog.dart';
import 'print_geometry.dart';
import 'support_analysis.dart';
import 'printer_setup.dart';
import 'model_cut.dart';
import 'plate_geometry.dart';
import 'workspace_history.dart';
import 'studio_project.dart';
import 'project_optimizer.dart';
import 'local_slicer.dart';
import 'slicer_page.dart';
export 'plate_geometry.dart';

class BuildPlatePage extends StatefulWidget {
  const BuildPlatePage({super.key,required this.pickPart,this.initialPart,this.initialParts = const [],this.initialScale = 1,this.bed = const PrinterBed(250,250,250),this.printer = 'Anycubic Kobra S1',this.slicer='Anycubic Slicer Next',this.nozzle='0.4',this.project,this.repository,this.openSettings=false});
  final Future<PlatePart?> Function() pickPart;
  final PlatePart? initialPart;
  final List<PlatePart> initialParts;
  final double initialScale;
  final PrinterBed bed;
  final String printer,slicer,nozzle;
  final StudioProject? project;
  final StudioProjectRepository? repository;
  final bool openSettings;
  @override State<BuildPlatePage> createState() => _BuildPlatePageState();
}
class _BuildPlatePageState extends State<BuildPlatePage> {
  List<PlatePlacement> parts = [];
  final images = <String,ui.Image>{};
  final thumbnailTokens = <String,int>{};
  final history=WorkspaceHistory();
  PlateSnapshot? dragBefore;
  bool dragRecorded=false;
  PrintProject? recipe;
  late String projectId=widget.project?.id??DateTime.now().microsecondsSinceEpoch.toString();
  late String projectName=widget.project?.name??widget.initialPart?.name??'Druckprojekt';
  late final repository=widget.repository??StudioProjectRepository();
  PrinterBed get activeBed=>widget.project?.bed??widget.bed;
  String get activePrinter=>widget.project?.printer??widget.printer;
  String get activeSlicer=>widget.project?.slicer??widget.slicer;
  String get activeNozzle=>recipe?.nozzle??widget.project?.nozzle??widget.nozzle;
  PlateSnapshot snapshot()=>PlateSnapshot(parts,selected);
  void remember()=>history.record(snapshot());
  void restore(PlateSnapshot value){setState((){parts=value.parts;selected=value.selected;});for(final p in parts){unawaited(thumbnail(p));}}
  void undo()=>restore(history.undo(snapshot()));
  void redo()=>restore(history.redo(snapshot()));
  StudioProject currentProject()=>StudioProject(id:projectId,name:projectName,printer:activePrinter,slicer:activeSlicer,
    nozzle:activeNozzle,bed:activeBed,parts:List.unmodifiable(parts),recipe:recipe);
  Future<void> saveProject()async{
    setState((){busy=true;error=null;});
    try{await repository.save(currentProject());if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Projekt mit allen Modellen gespeichert.')));}
    catch(_){if(mounted)setState(()=>error='Projekt konnte nicht gespeichert werden. Bitte erneut versuchen.');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> exportProject()async{
    setState((){busy=true;error=null;});
    try{
      final bytes=await compute(encodeStudioProject,currentProject());if(!mounted)return;
      final name=projectName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'),'_');
      final target=await FilePicker.platform.saveFile(dialogTitle:'Projektdatei speichern',fileName:'$name.printproject',
        type:FileType.custom,allowedExtensions:['printproject'],bytes:bytes);
      if(target!=null&&(Platform.isWindows||Platform.isLinux||Platform.isMacOS))await File(target).writeAsBytes(bytes,flush:true);
    }catch(_){if(mounted)setState(()=>error='Projektdatei konnte nicht exportiert werden.');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> editRecipe()async{
    final p=recipe??PrintProject(id:projectId,fileName:projectName,dimensions:'${parts.length} Teile',printer:activePrinter,slicer:activeSlicer,
      nozzle:activeNozzle,bed:activeBed,supportStatus:'Im Slicer prüfen',supportReason:'Stützen werden für die gesamte Druckplatte berechnet.');
    final value=await Navigator.push<PrintProject>(context,MaterialPageRoute(builder:(_)=>ProjectOptimizerPage(project:p,returnProject:true,onProjectSaved:(updated)async{
      await repository.save(currentProject().copy(recipe:updated));if(mounted)setState(()=>recipe=updated);
    })));
    if(value!=null&&mounted)setState(()=>recipe=value);
  }
  late double bedWidth = activeBed.width,bedDepth = activeBed.depth;
  int selected = -1,counter = 0;
  int? movingPointer;
  bool busy = false;
  String? error;
  @override void initState() {
    super.initState();
    if(widget.project!=null){parts=List.of(widget.project!.parts);recipe=widget.project!.recipe;selected=parts.isEmpty?-1:0;for(final p in parts){unawaited(thumbnail(p));}}
    if (widget.initialPart != null) addPart(widget.initialPart!,widget.initialScale);
    for (final part in widget.initialParts) { addPart(part,1); }
    if(widget.openSettings)WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)editRecipe();});
  }
  void addPart(PlatePart part,double scale) {
    while(parts.any((p)=>p.id=='$counter')){counter++;}
    final id = '${counter++}';
    final placed = placeNextPart(part,parts,bedWidth,bedDepth,id,scale: scale);
    parts = [...parts,placed]; selected = parts.length-1;
    unawaited(thumbnail(placed));
  }
  Future<void> thumbnail(PlatePlacement placed) async {
    final token = (thumbnailTokens[placed.id] ?? 0)+1; thumbnailTokens[placed.id] = token;
    try {
      final request = MeshRenderRequest(placed.part.vertices,160,160,0,0,1);
      final pixels = await compute(renderMesh,request);
      if (!mounted) return;
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(pixels,160,160,ui.PixelFormat.rgba8888,completer.complete);
      final image = await completer.future;
      if (!mounted || thumbnailTokens[placed.id] != token || !parts.any((p) => p.id == placed.id)) { image.dispose(); return; }
      final old = images[placed.id];
      setState(() => images[placed.id] = image);
      if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    } catch (_) { /* Outline remains usable if the thumbnail cannot be rendered. */ }
  }
  Future<void> pick() async {
    setState(() { busy = true; error = null; });
    try {
      final part = await widget.pickPart();
      if (!mounted || part == null) return;
      final faces = parts.fold<int>(0,(a,p) => a+p.part.vertices.length~/9)+part.vertices.length~/9;
      if (84+faces*50 > 100*1024*1024) throw const FormatException('Alle Teile zusammen überschreiten 100 MB als STL.');
      setState(() {remember();addPart(part,1);});
    } catch (e) { if (mounted) setState(() => error = e is FormatException ? e.message : 'Datei konnte nicht hinzugefügt werden. Größe oder Format prüfen.'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  void change(PlatePlacement next) => changeAt(selected,next);
  void changeAt(int index,PlatePlacement next,{bool record=true}) => setState(() { if(record)remember();parts = [...parts]..[index] = next; });
  Future<void> align() async {
    setState(() { busy = true; error = null; });
    try {
      final result = await compute(autoOrientPlate,(List<PlatePlacement>.unmodifiable(parts),bedWidth,bedDepth,activeBed.height));
      if (!mounted) return;
      setState(() { remember();parts = result.$1; });
      for (final p in parts) { unawaited(thumbnail(p)); }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.$2 == 0
        ? 'Alle Teile geometrisch ausgerichtet und neu angeordnet.' : '${result.$2} Teile mit unklarer Geometrie: Drucklage im Slicer prüfen.')));
    } catch (_) { if (mounted) setState(() => error = 'Automatisches Ausrichten fehlgeschlagen. Anordnung bleibt erhalten.'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  PlatePlacement clamp(PlatePlacement p) => p.copy(
    x: p.width <= bedWidth ? p.x.clamp(p.width/2,bedWidth-p.width/2).toDouble() : p.x,
    y: p.depth <= bedDepth ? p.y.clamp(p.depth/2,bedDepth-p.depth/2).toDouble() : p.y);
  Future<void> resize() async {
    final p = parts[selected];
    final scale = await showDialog<double>(context: context,builder: (_) => ModelSizeDialog(
      scale: p.scale,width: p.turns.isOdd ? p.part.depth : p.part.width,editWidth: false));
    if (mounted && scale != null) change(clamp(p.copy(scale: scale)));
  }
  Future<void> cutSelected() async {
    final old = parts[selected];
    final vertices = old.turns == 0 ? old.part.vertices : await compute(rotatePlateForCut,(old.part.vertices,old.turns));
    if (!mounted) return;
    final input = PlatePart(name: old.part.name,vertices: vertices,unitScale: old.part.unitScale,
      width: old.turns.isOdd ? old.part.depth : old.part.width,depth: old.turns.isOdd ? old.part.width : old.part.depth,height: old.part.height);
    final cut = await requestModelCut(context,input,old.scale,bed: activeBed);
    if (cut == null || !mounted) return;
    setState(() {
      remember();parts = parts.where((p) => p.id != old.id).toList();
      for (final part in cut) { addPart(part,1); }
    });
    final image = images.remove(old.id);
    if (image != null) WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
  }
  Future<void> position() async {
    final p = parts[selected];
    final xy = await showDialog<(double,double)>(context: context,builder: (_) => _CoordinatesDialog(
      title: 'Position der Teilmitte',first: p.x,second: p.y,firstLabel: 'X in mm',secondLabel: 'Y in mm'));
    if (mounted && xy != null) change(p.copy(x: xy.$1,y: xy.$2));
  }
  bool get overlaps {
    for (var i = 0; i < parts.length; i++) {
      for (var j = i+1; j < parts.length; j++) { if (parts[i].bounds.overlaps(parts[j].bounds)) return true; }
    }
    return false;
  }
  Future<void> save() async {
    if (overlaps) {
      final yes = await showDialog<bool>(context: context,builder: (ctx) => AlertDialog(
        title: const Text('Platzbereiche überlappen'),
        content: const Text('Die Begrenzungsrechtecke überlappen. Die tatsächlichen Konturen und Abstände im Slicer prüfen.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx,false),child: const Text('Anpassen')),
          FilledButton(onPressed: () => Navigator.pop(ctx,true),child: const Text('Trotzdem speichern'))]));
      if (yes != true || !mounted) return;
    }
    setState(() { busy = true; error = null; });
    try {
      final bytes = await compute(encodePlateStl,List<PlatePlacement>.unmodifiable(parts));
      if (!mounted) return;
      final target = await FilePicker.platform.saveFile(dialogTitle: 'Druckplatte speichern',
        fileName: '3DPrint_Druckplatte.stl',type: FileType.custom,allowedExtensions: ['stl'],bytes: bytes);
      if (target == null) return;
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) await File(target).writeAsBytes(bytes,flush: true);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Alle Teile als neue STL gespeichert.')));
    } catch (_) { if (mounted) setState(() => error = 'Druckplatte konnte nicht gespeichert werden.'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override void dispose() { for (final image in images.values) { image.dispose(); } super.dispose(); }
  @override Widget build(BuildContext context) {
    final outOfBounds = parts.any((p) => !p.fits(bedWidth,bedDepth,activeBed.height));
    return Scaffold(appBar: AppBar(title: const Text('Druckplatte'),actions: [
      IconButton(tooltip: 'Datei hinzufügen',onPressed: busy ? null : pick,icon: const Icon(Icons.add)),
      PopupMenuButton<String>(tooltip:'Speichern und exportieren',enabled:!busy&&parts.isNotEmpty,
        onSelected:(value){if(value=='project'){saveProject();}else if(value=='archive'){exportProject();}else{save();}},
        itemBuilder:(_)=>[
          const PopupMenuItem(value:'project',child:Text('Projekt speichern')),
          const PopupMenuItem(value:'archive',child:Text('Projektdatei exportieren')),
          PopupMenuItem(value:'stl',enabled:!outOfBounds,child:const Text('STL exportieren')),
        ],child:const Padding(padding:EdgeInsets.symmetric(horizontal:14),child:Center(child:Text('Speichern')))),

    ]),body: SafeArea(top: false,child: ListView(padding: const EdgeInsets.all(16),children: [
      Text('${activePrinter}: ${bedWidth.toStringAsFixed(0)} × ${bedDepth.toStringAsFixed(0)} × ${activeBed.height.toStringAsFixed(0)} mm'),
      Row(children:[IconButton(tooltip:'Rückgängig',onPressed:!busy&&history.canUndo?undo:null,icon:const Icon(Icons.undo)),
        IconButton(tooltip:'Wiederholen',onPressed:!busy&&history.canRedo?redo:null,icon:const Icon(Icons.redo)),
        const Spacer(),TextButton.icon(onPressed:busy?null:editRecipe,icon:const Icon(Icons.tune),label:const Text('Einstellungen'))]),
      const SizedBox(height:8),
      FilledButton.icon(onPressed:busy||parts.isEmpty||recipe==null||outOfBounds||!supportsLocalSlicer(currentProject())?null:
        ()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>SlicerPage(project:currentProject()))),
        icon:const Icon(Icons.layers_outlined),label:const Text('G-Code erstellen')),
      if(recipe==null)const Padding(padding:EdgeInsets.symmetric(vertical:8),child:Text('Zuerst unter Einstellungen die Fragen zum Modell beantworten.')),
      if(!supportsLocalSlicer(currentProject()))const Text('Lokaler Slicer zunächst für Kobra S1 mit 0,4-mm-Düse. Andere Profile folgen.'),
      const SizedBox(height:8),
      const Text('Teil antippen und verschieben. Weitere Datei oben mit + hinzufügen.'),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: busy || parts.isEmpty ? null : align,icon: const Icon(Icons.auto_fix_high),label: const Text('Automatisch ausrichten')),
      LayoutBuilder(builder: (context,constraints) {
        final pixelsPerMm = constraints.maxWidth/bedWidth;
        return AspectRatio(aspectRatio: bedWidth/bedDepth,child: ClipRRect(borderRadius: BorderRadius.circular(16),
          child: Stack(clipBehavior: Clip.hardEdge,children: [
            Positioned.fill(child: CustomPaint(painter: _PlateGrid(bedWidth,bedDepth))),
            for (var i = 0; i < parts.length; i++) ...[
              if (images[parts[i].id] != null) Positioned(
                left: (parts[i].x-parts[i].part.unitScale*parts[i].scale/.85)*pixelsPerMm,
                top: (bedDepth-parts[i].y-parts[i].part.unitScale*parts[i].scale/.85)*pixelsPerMm,
                width: parts[i].part.unitScale*parts[i].scale/.425*pixelsPerMm,
                height: parts[i].part.unitScale*parts[i].scale/.425*pixelsPerMm,
                child: IgnorePointer(child: Transform.rotate(angle: -parts[i].turns*math.pi/2,
                  child: RawImage(image: images[parts[i].id],fit: BoxFit.fill)))),
              Positioned(left: parts[i].bounds.left*pixelsPerMm,top: (bedDepth-parts[i].bounds.bottom)*pixelsPerMm,
                width: math.max(16,parts[i].width*pixelsPerMm),height: math.max(16,parts[i].depth*pixelsPerMm),
                child: RawGestureDetector(key: ValueKey('plate-hit-$i'),behavior: HitTestBehavior.opaque,
                  gestures: {EagerGestureRecognizer: GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                    () => EagerGestureRecognizer(), (_) {})},
                  child: Listener(behavior: HitTestBehavior.opaque,
                  onPointerDown: busy ? null : (event) {
                    if (movingPointer != null) return;
                    movingPointer = event.pointer;dragBefore=snapshot();dragRecorded=false;
                    setState(() => selected = i);
                  },
                  onPointerMove: busy ? null : (event) {
                    if (movingPointer != event.pointer) return;
                    if(!dragRecorded){history.record(dragBefore!);dragRecorded=true;}
                    changeAt(i,clamp(parts[i].copy(
                      x: parts[i].x+event.delta.dx/pixelsPerMm,y: parts[i].y-event.delta.dy/pixelsPerMm)),record:false);
                  },
                  onPointerUp: (event) { if (movingPointer == event.pointer) movingPointer = null; },
                  onPointerCancel: (event) { if (movingPointer == event.pointer) movingPointer = null; },
                  child: DecoratedBox(decoration: BoxDecoration(
                    border: Border.all(color: i == selected ? const Color(0xffb9a6ff) : const Color(0xff8294b5),width: i == selected ? 2 : 1),
                    color: images[parts[i].id] == null ? const Color(0x333c99bd) : null),
                    child: Align(alignment: Alignment.topLeft,child: Text('${i+1}',style: const TextStyle(color: Colors.white,fontWeight: FontWeight.bold))))))),
            ],
          ])));
      }),
      if (busy) const LinearProgressIndicator(),
      if (error != null) Text(error!,style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (outOfBounds) Text('Mindestens ein Teil passt nicht in den Bauraum. Größe, Drucklage oder Position ändern.',style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (overlaps) const Text('Platzbereiche überlappen – Konturen und Abstände prüfen.'),
      if (parts.isEmpty) Padding(padding: const EdgeInsets.all(24),child: FilledButton.icon(
        onPressed: busy ? null : pick,icon: const Icon(Icons.add),label: const Text('Erste Datei hinzufügen'))),
      if (selected >= 0 && selected < parts.length) ...[
        const SizedBox(height: 12),Text('Ausgewählt: ${parts[selected].part.name}',style: Theme.of(context).textTheme.titleMedium),
        Text('X ${parts[selected].x.toStringAsFixed(1)} · Y ${parts[selected].y.toStringAsFixed(1)} mm · Größe ${(parts[selected].scale*100).toStringAsFixed(1)} %'),
        Wrap(spacing: 8,runSpacing: 8,children: [
          OutlinedButton(onPressed: busy ? null : position,child: const Text('X / Y eingeben')),
          OutlinedButton(onPressed: busy ? null : resize,child: const Text('Größe ändern')),
          if (Platform.isAndroid) OutlinedButton(onPressed: busy ? null : cutSelected,child: const Text('Teilen & verbinden')),
          OutlinedButton(onPressed: busy ? null : () => change(clamp(parts[selected].copy(turns: (parts[selected].turns+1)%4))),child: const Text('90° drehen')),
        ]),
      ],
      const SizedBox(height: 12),
      for (var i = 0; i < parts.length; i++) Card(child: ListTile(
        selected: i == selected,leading: CircleAvatar(child: Text('${i+1}')),title: Text(parts[i].part.name),
        subtitle: Text('${parts[i].width.toStringAsFixed(1)} × ${parts[i].depth.toStringAsFixed(1)} × ${(parts[i].part.height*parts[i].scale).toStringAsFixed(1)} mm'),
        onTap: () => setState(() => selected = i),trailing: IconButton(tooltip: 'Teil entfernen',onPressed: busy ? null : () {
          final old = parts[i];
          setState(() { remember();parts = [...parts]..removeAt(i); selected = parts.isEmpty ? -1 : math.min(i,parts.length-1); });
          final image = images.remove(old.id);
          if (image != null) WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
        },icon: const Icon(Icons.close)))),
      const Text('STL speichert Geometrie und Positionen, keine 3MF-Farben oder Materialzuweisungen. Verbindungspaare immer gleich skalieren. Vor dem Drucken im Slicer prüfen.'),
    ])));
  }
}
class _PlateGrid extends CustomPainter {
  _PlateGrid(this.width,this.depth);
  final double width,depth;
  @override void paint(Canvas canvas,Size size) {
    canvas.drawRect(Offset.zero & size,Paint()..color = const Color(0xff211f34));
    final paint = Paint()..color = const Color(0xff403950)..strokeWidth = 1;
    final step = math.max(10,(math.max(width,depth)/50/10).ceil()*10).toDouble();
    for (var x = 0.0; x <= width; x += step) canvas.drawLine(Offset(x/width*size.width,0),Offset(x/width*size.width,size.height),paint);
    for (var y = 0.0; y <= depth; y += step) canvas.drawLine(Offset(0,y/depth*size.height),Offset(size.width,y/depth*size.height),paint);
  }
  @override bool shouldRepaint(_PlateGrid old) => width != old.width || depth != old.depth;
}
class _CoordinatesDialog extends StatefulWidget {
  const _CoordinatesDialog({required this.title,required this.first,required this.second,
    required this.firstLabel,required this.secondLabel,this.positive = false});
  final String title,firstLabel,secondLabel;
  final double first,second;
  final bool positive;
  @override State<_CoordinatesDialog> createState() => _CoordinatesDialogState();
}
class _CoordinatesDialogState extends State<_CoordinatesDialog> {
  final form = GlobalKey<FormState>();
  late final first = TextEditingController(text: widget.first.toStringAsFixed(2));
  late final second = TextEditingController(text: widget.second.toStringAsFixed(2));
  double? number(String? text) => double.tryParse((text ?? '').trim().replaceAll(',','.'));
  String? validate(String? text) {
    final value = number(text);
    return value == null || !value.isFinite || value.abs() > 100000 || (widget.positive && value < 1)
      ? 'Bitte einen gültigen Millimeterwert eingeben.' : null;
  }
  @override void dispose() { first.dispose(); second.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AlertDialog(title: Column(mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,children: [Text(widget.title),
      FilledButton(onPressed: () {
        if (form.currentState!.validate()) Navigator.pop(context,(number(first.text)!,number(second.text)!));
      },child: const Text('Übernehmen'))]),content: Form(key: form,child: Column(mainAxisSize: MainAxisSize.min,children: [
        TextFormField(controller: first,decoration: InputDecoration(labelText: widget.firstLabel),validator: validate,
          keyboardType: const TextInputType.numberWithOptions(decimal: true,signed: true)),
        const SizedBox(height: 12),
        TextFormField(controller: second,decoration: InputDecoration(labelText: widget.secondLabel),validator: validate,
          keyboardType: const TextInputType.numberWithOptions(decimal: true,signed: true)),
      ])));
}
