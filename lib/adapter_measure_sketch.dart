import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'adapter_geometry.dart';
import 'adapter_request.dart';

/// A schematic section through the current template. No drawing proportions
/// are inferred dimensions: only explicitly entered values appear as numbers.
class AdapterMeasureSketch extends StatelessWidget {
  const AdapterMeasureSketch({super.key,required this.draft,required this.onEdit});
  final AdapterDraft draft;
  final ValueChanged<AdapterField> onEdit;
  static String millimetres(double value)=>'${value.toStringAsFixed(2).replaceAll(RegExp(r'0+$'),'').replaceAll(RegExp(r'\.$'),'').replaceAll('.',',')} mm';
  @override Widget build(BuildContext context){
    final fields=<(AdapterField,String,String,Offset)>[
      (AdapterField.first,'Seite A',draft.first==null?'Innen / außen?':'${draft.first!.kind==DiameterKind.inner?'Innen':'Außen'} Ø ${millimetres(draft.first!.diameter)}',const Offset(.19,.16)),
      (AdapterField.second,'Seite B',draft.second==null?'Innen / außen?':'${draft.second!.kind==DiameterKind.inner?'Innen':'Außen'} Ø ${millimetres(draft.second!.diameter)}',const Offset(.81,.16)),
      (AdapterField.wall,'Wand',draft.wall==null?'Maß fehlt':millimetres(draft.wall!),const Offset(.50,.36)),
      (AdapterField.socket,'Steckbereich je Seite',draft.socket==null?'Maß fehlt':millimetres(draft.socket!),const Offset(.50,.72)),
      (AdapterField.length,'Gesamtlänge',draft.length==null?'Maß fehlt':millimetres(draft.length!),const Offset(.50,.94)),
    ];
    return Column(mainAxisSize:MainAxisSize.min,children:[
      const Text('Schematischer Längsschnitt · nicht maßstabsgetreu',textAlign:TextAlign.center,style:TextStyle(fontSize:12)),
      const SizedBox(height:12),
      LayoutBuilder(builder:(context,c)=>SizedBox(height:360,child:Stack(children:[
        Positioned.fill(child:CustomPaint(painter:_SectionPainter(firstInner:draft.first?.kind==DiameterKind.inner,secondInner:draft.second?.kind==DiameterKind.inner))),
        for(final field in fields)Positioned(
          left:field.$4.dx*c.maxWidth-(field.$1==AdapterField.first||field.$1==AdapterField.second?c.maxWidth*.18:c.maxWidth*.28),
          top:field.$4.dy*320-24,
          width:field.$1==AdapterField.first||field.$1==AdapterField.second?c.maxWidth*.36:c.maxWidth*.56,
          child:Semantics(button:true,label:'${field.$2}: ${field.$3}. Maß bearbeiten',child:OutlinedButton(
            key:ValueKey('sketch-${field.$1.name}'),
            style:OutlinedButton.styleFrom(backgroundColor:Theme.of(context).colorScheme.surface,padding:const EdgeInsets.symmetric(horizontal:4,vertical:8)),
            onPressed:()=>onEdit(field.$1),child:Column(mainAxisSize:MainAxisSize.min,children:[
              Text(field.$2,textAlign:TextAlign.center,style:const TextStyle(fontSize:11)),
              Text(field.$3,textAlign:TextAlign.center,style:const TextStyle(fontSize:12,fontWeight:FontWeight.w700)),
            ]),
          )),
        ),
      ]))),
      const Text('Tippe auf ein Maß. „Innen“ misst die freie Öffnung, „Außen“ schließt die Wand mit ein.',style:TextStyle(fontSize:12)),
    ]);
  }
}

class _SectionPainter extends CustomPainter {
  const _SectionPainter({required this.firstInner,required this.secondInner});
  final bool firstInner,secondInner;
  @override void paint(Canvas canvas,Size size){
    Offset p(double x,double y)=>Offset(size.width*x,320*y);
    final outline=Paint()..color=const Color(0xff6550c7)..style=PaintingStyle.stroke..strokeWidth=2;
    final fill=Paint()..color=const Color(0xffded7ff);
    void material(List<Offset> points){final path=Path()..addPolygon(points,true);canvas.drawPath(path,fill);canvas.drawPath(path,outline);}
    material([p(.12,.32),p(.30,.32),p(.70,.28),p(.88,.28),p(.88,.34),p(.70,.34),p(.30,.38),p(.12,.38)]);
    material([p(.12,.62),p(.30,.62),p(.70,.66),p(.88,.66),p(.88,.72),p(.70,.72),p(.30,.68),p(.12,.68)]);
    final dimension=Paint()..color=const Color(0xff4b455e)..strokeWidth=1.3;
    void line(Offset a,Offset b)=>canvas.drawLine(a,b,dimension);
    void arrow(Offset a,Offset b){
      line(a,b);final angle=math.atan2(b.dy-a.dy,b.dx-a.dx);
      for(final pair in [(a,angle),(b,angle+math.pi)]){
        for(final sign in [-1,1])line(pair.$1,pair.$1+Offset(math.cos(pair.$2+sign*.45)*7,math.sin(pair.$2+sign*.45)*7));
      }
    }
    // Diameter dimensions explicitly show both the bore and outer surface;
    // the labels preserve which one the user selected.
    final aTop=firstInner ? .38 : .32,aBottom=firstInner ? .62 : .68;
    arrow(p(.08,aTop),p(.08,aBottom));line(p(.08,aTop),p(.12,aTop));line(p(.08,aBottom),p(.12,aBottom));
    line(p(.08,aTop),p(.19,.24));
    final bTop=secondInner ? .34 : .28,bBottom=secondInner ? .66 : .72;
    arrow(p(.92,bTop),p(.92,bBottom));line(p(.88,bTop),p(.92,bTop));line(p(.88,bBottom),p(.92,bBottom));
    line(p(.92,bTop),p(.81,.24));
    arrow(p(.25,.32),p(.25,.38));line(p(.25,.35),p(.50,.37));
    arrow(p(.12,.79),p(.30,.79));line(p(.12,.68),p(.12,.80));line(p(.30,.68),p(.30,.80));
    arrow(p(.70,.79),p(.88,.79));line(p(.70,.72),p(.70,.80));line(p(.88,.72),p(.88,.80));
    line(p(.12,.87),p(.12,.98));line(p(.88,.87),p(.88,.98));arrow(p(.12,.98),p(.88,.98));
  }
  @override bool shouldRepaint(_SectionPainter oldDelegate)=>firstInner!=oldDelegate.firstInner||secondInner!=oldDelegate.secondInner;
}
