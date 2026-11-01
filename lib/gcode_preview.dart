import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'printer_setup.dart';

class GcodeLayer {
  const GcodeLayer(this.number,this.z,this.segments);
  final int number;final double z;
  final Float32List segments; // x0,y0,x1,y1,feature; travel=5.
}
class GcodePreview {
  const GcodePreview(this.layers,this.outsideBed,this.extrusionMoves,this.seconds,this.filamentMetres,{this.simplified=false});
  final List<GcodeLayer> layers;
  final bool outsideBed, simplified;final int extrusionMoves;
  final double? seconds,filamentMetres;
}
class _Floats {
  final blocks=<Float32List>[];var length=0;
  void add(double value){if(length%256==0)blocks.add(Float32List(256));blocks.last[length%256]=value;length++;}
  Float32List finish(){final result=Float32List(length);var offset=0;for(final block in blocks){final n=math.min(block.length,length-offset);result.setRange(offset,offset+n,block);offset+=n;}return result;}
}
const maxGcodeBytes=512*1024*1024;
const maxPreviewSegments=300000;

class _GcodeParser {
  _GcodeParser(this.bed,{this.maxSegments=maxPreviewSegments}) {
    if(!bed.valid||maxSegments<10000)throw const FormatException('Der Bauraum oder die Vorschaugrenze ist ungültig.');
  }
  final PrinterBed bed;
  final int maxSegments;
  final paths=<_Floats>[],numbers=<int>[],heights=<double>[];
  var x=0.0,y=0.0,z=0.0,e=0.0,absolute=true,absoluteE=true,layer=-1,feature=0,moves=0,count=0,outside=false;
  var sampleEvery=1,stored=0;
  double? seconds,metres;
  final words=RegExp(r'([XYZE])\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+))');
  void thin(){
    stored=0;sampleEvery*=2;
    for(var i=0;i<paths.length;i++){
      final values=paths[i].finish(),next=_Floats();
      for(var j=0;j<values.length;j+=10){
        for(var k=0;k<5;k++){next.add(values[j+k]);}
        stored++;
      }
      paths[i]=next;
    }
  }
  void addLine(String raw){
    if(raw.length>65536)throw const FormatException('Eine G-Code-Zeile ist zu lang.');
    final line=raw.trim();
    if(line.startsWith(';LAYER:')){
      final number=int.tryParse(line.substring(7));if(number==null)return;
      if(paths.length>=10000)throw const FormatException('Zu viele Schichten für die Vorschau.');
      paths.add(_Floats());numbers.add(number);heights.add(z);layer=paths.length-1;return;
    }
    if(line.startsWith(';TIME:'))seconds=double.tryParse(line.substring(6));
    if(line.startsWith(';Filament used:')){
      final value=RegExp(r'([0-9.]+)\s*m').firstMatch(line);if(value!=null)metres=double.tryParse(value.group(1)!);
    }
    if(line.startsWith(';TYPE:')){
      final type=line.substring(6);feature=type.contains('SUPPORT')?3:type.contains('SKIRT')||type.contains('BRIM')?4:
        type.contains('FILL')?1:type.contains('SKIN')?2:0;return;
    }
    final command=line.split(';').first.trim();
    if(command.isEmpty)return;
    final code=RegExp(r'^([GMT]\d+)\b').firstMatch(command)?.group(1);
    if(code=='G90'){absolute=true;return;}if(code=='G91'){absolute=false;return;}
    if(code=='M82'){absoluteE=true;return;}if(code=='M83'){absoluteE=false;return;}
    if(code=='G20')throw const FormatException('Zoll-G-Code wird nicht unterstützt.');
    if(code=='G2'||code=='G3')throw const FormatException('Bogenbefehle werden in dieser Vorschau noch nicht unterstützt.');
    if(code!='G0'&&code!='G1'&&code!='G92')return;
    if(RegExp(r'[XYZE]\s*[-+]?(?:nan|inf)',caseSensitive:false).hasMatch(command))throw const FormatException('Ungültige G-Code-Koordinaten.');
    final values={for(final m in words.allMatches(command))m.group(1)!:double.parse(m.group(2)!)};
    if(values.values.any((v)=>!v.isFinite||v.abs()>1e7))throw const FormatException('Ungültige G-Code-Koordinaten.');
    if(code=='G92'){
      if(values.keys.any((k)=>k!='E'))throw const FormatException('Geänderte Koordinatenursprünge werden nicht unterstützt.');
      e=values['E']??e;return;
    }
    double axis(String name,double previous)=>values.containsKey(name)?(absolute?values[name]!:previous+values[name]!):previous;
    final nx=axis('X',x),ny=axis('Y',y),nz=axis('Z',z);
    final ne=values.containsKey('E')?(absoluteE?values['E']!:e+values['E']!):e;
    if(nx<-.05||ny<-.05||nz<-.05||nx>bed.width+.05||ny>bed.depth+.05||nz>bed.height+.05)outside=true;
    if(layer>=0&&((nx-x).abs()>1e-6||(ny-y).abs()>1e-6)){
      count++;
      final extrusion=ne>e+1e-6;
      if(count%sampleEvery==0||paths[layer].length==0){
        if(stored>=maxSegments)thin();
        for(final value in [x,y,nx,ny,(extrusion?feature:5).toDouble()]){paths[layer].add(value);}
        stored++;
      }
      if(extrusion){moves++;heights[layer]=nz;}
    }
    x=nx;y=ny;z=nz;e=ne;
  }
  GcodePreview finish(){
    if(paths.isEmpty||moves==0)throw const FormatException('Keine druckbaren Schichten im G-Code gefunden.');
    return GcodePreview([for(var i=0;i<paths.length;i++)GcodeLayer(numbers[i],heights[i],paths[i].finish())],outside,moves,seconds,metres,simplified:sampleEvery>1);
  }
}
GcodePreview parseGcode((String,PrinterBed) input){
  final parser=_GcodeParser(input.$2);
  for(final line in const LineSplitter().convert(input.$1)){parser.addLine(line);}
  return parser.finish();
}
Future<GcodePreview> parseGcodeFile((String,PrinterBed) input)async{
  final file=File(input.$1);
  if(await file.length()>maxGcodeBytes)throw const FormatException('G-Code ist größer als 512 MB.');
  final parser=_GcodeParser(input.$2);
  var pending='',bytes=0;
  await for(final chunk in file.openRead().map((chunk){
    bytes+=chunk.length;
    if(bytes>maxGcodeBytes)throw const FormatException('G-Code ist größer als 512 MB.');
    return chunk;
  }).transform(utf8.decoder)){
    final text=pending+chunk;
    var offset=0,end=text.indexOf('\n');
    while(end>=0){parser.addLine(text.substring(offset,end));offset=end+1;end=text.indexOf('\n',offset);}
    pending=text.substring(offset);
    if(pending.length>65536)throw const FormatException('Eine G-Code-Zeile ist zu lang.');
  }
  if(pending.isNotEmpty)parser.addLine(pending);
  return parser.finish();
}

const pathColors=[Color(0xffb9a6ff),Color(0xff6de1b5),Color(0xffffcc7a),Color(0xffff7f8d),Color(0xff8fcaff),Color(0xff626077)];
class LayerPreview extends StatefulWidget {
  const LayerPreview({super.key,required this.preview,required this.bed});
  final GcodePreview preview;final PrinterBed bed;
  @override State<LayerPreview> createState()=>_LayerPreviewState();
}
class _LayerPreviewState extends State<LayerPreview>{
  int selected=0;bool travel=false;
  @override Widget build(BuildContext context){
    final layer=widget.preview.layers[selected];
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('Schicht ${selected+1} / ${widget.preview.layers.length}',style:Theme.of(context).textTheme.titleLarge),
      if(widget.preview.simplified)const Text('Große Datei: Die Vorschau zeigt eine reduzierte Auswahl echter Druckbahnen. Der gesamte G-Code wurde auf den Bauraum geprüft und bleibt vollständig gespeichert.'),
      Text('Z ${layer.z.toStringAsFixed(2)} mm · ${widget.preview.extrusionMoves} Druckbewegungen'),const SizedBox(height:12),
      ClipRRect(borderRadius:BorderRadius.circular(22),child:Container(color:const Color(0xff1c1a2d),height:360,
        child:InteractiveViewer(minScale:.5,maxScale:10,child:CustomPaint(painter:_ToolpathPainter(layer,widget.bed,travel),child:const SizedBox.expand())))),
      Slider(value:selected.toDouble(),min:0,max:math.max(1,widget.preview.layers.length-1).toDouble(),
        divisions:math.max(1,widget.preview.layers.length-1),onChanged:widget.preview.layers.length==1?null:(v)=>setState(()=>selected=v.round())),
      Wrap(spacing:14,runSpacing:8,children:[for(var i=0;i<5;i++)Row(mainAxisSize:MainAxisSize.min,children:[
        Container(width:9,height:9,decoration:BoxDecoration(color:pathColors[i],shape:BoxShape.circle)),const SizedBox(width:5),
        Text(['Wände','Füllung','Deckflächen','Stützen','Haftung'][i],style:const TextStyle(fontSize:12)),
      ])]),
      SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Leerfahrten anzeigen'),value:travel,onChanged:(v)=>setState(()=>travel=v)),
      const Text('Vorschau aus den tatsächlich erzeugten G-Code-Bewegungen. Startmakros des Druckers werden nicht simuliert.',style:TextStyle(fontSize:12)),
    ]);
  }
}
class _ToolpathPainter extends CustomPainter {
  const _ToolpathPainter(this.layer,this.bed,this.travel);
  final GcodeLayer layer;final PrinterBed bed;final bool travel;
  @override void paint(Canvas canvas,Size size){
    final scale=math.min((size.width-28)/bed.width,(size.height-28)/bed.depth);
    final dx=(size.width-bed.width*scale)/2,dy=(size.height-bed.depth*scale)/2;
    canvas.save();canvas.translate(dx,dy);
    final grid=Paint()..color=const Color(0xff403950)..strokeWidth=.6;
    for(var x=0.0;x<=bed.width;x+=10){canvas.drawLine(Offset(x*scale,0),Offset(x*scale,bed.depth*scale),grid);}
    for(var y=0.0;y<=bed.depth;y+=10){canvas.drawLine(Offset(0,y*scale),Offset(bed.width*scale,y*scale),grid);}
    canvas.clipRect(Rect.fromLTWH(0,0,bed.width*scale,bed.depth*scale));
    for(var type=5;type>=0;type--){
      if(type==5&&!travel)continue;
      final path=Path(),v=layer.segments;
      for(var i=0;i<v.length;i+=5)if(v[i+4].round()==type){path.moveTo(v[i]*scale,(bed.depth-v[i+1])*scale);path.lineTo(v[i+2]*scale,(bed.depth-v[i+3])*scale);}
      canvas.drawPath(path,Paint()..color=pathColors[type]..style=PaintingStyle.stroke..strokeWidth=(type == 5 ? 0.6 :math.max(1,.42*scale))..strokeCap=StrokeCap.round);
    }
    canvas.restore();
  }
  @override bool shouldRepaint(_ToolpathPainter old)=>old.layer!=layer||old.bed!=bed||old.travel!=travel;
}
