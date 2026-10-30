import 'dart:math' as math;
import 'dart:typed_data';
import 'build_plate.dart';

enum DiameterKind { inner,outer }
class AdapterPort {
  const AdapterPort(this.kind,this.diameter);
  final DiameterKind kind;final double diameter;
}
class AdapterSpec {
  const AdapterSpec({required this.first,required this.second,this.length=60,this.wall=2.5,this.socket=15});
  final AdapterPort first,second;final double length,wall,socket;
  String? validate(){
    if([first.diameter,second.diameter,length,wall,socket].any((v)=>!v.isFinite))return 'Alle Maße müssen gültige Zahlen sein.';
    if(first.diameter<2||second.diameter<2||first.diameter>1000||second.diameter>1000)return 'Durchmesser zwischen 2 und 1000 mm eintragen.';
    if(wall<.8||wall>30)return 'Wandstärke zwischen 0,8 und 30 mm eintragen.';
    if(socket<2||socket>500)return 'Stecktiefe zwischen 2 und 500 mm eintragen.';
    if(length<2*socket+1||length>2000)return 'Gesamtlänge muss mindestens zweimal Stecktiefe plus 1 mm sein.';
    for(final port in [first,second])if(port.kind==DiameterKind.outer&&port.diameter<=2*wall+.8)return 'Außendurchmesser ist zu klein für Wand und Innenöffnung.';
    return null;
  }
}
PlatePart buildAdapter(AdapterSpec spec){
  final error=spec.validate();if(error!=null)throw FormatException(error);
  double inner(AdapterPort port)=>port.diameter/2-(port.kind==DiameterKind.outer?spec.wall:0);
  final innerA=inner(spec.first),innerB=inner(spec.second),outerA=innerA+spec.wall,outerB=innerB+spec.wall;
  final maximum=math.max(outerA,outerB),unit=math.sqrt(8*maximum*maximum+spec.length*spec.length)/2;
  const count=128;final values=<double>[];
  final zs=[-spec.length/2,-spec.length/2+spec.socket,spec.length/2-spec.socket,spec.length/2];
  final radii=[[outerA,outerA,outerB,outerB],[innerA,innerA,innerB,innerB]];
  List<double> point(int side,int ring,int j){final angle=2*math.pi*(j%count)/count,r=radii[side][ring];return [r*math.cos(angle)/unit,r*math.sin(angle)/unit,zs[ring]/unit];}
  void triangle(List<double> a,List<double> b,List<double> c){values.addAll(a);values.addAll(b);values.addAll(c);}
  for(var ring=0;ring<3;ring++)for(var j=0;j<count;j++){
    for(var side=0;side<2;side++){
      final a=point(side,ring,j),b=point(side,ring,j+1),c=point(side,ring+1,j),d=point(side,ring+1,j+1);
      if(side==0){triangle(a,b,c);triangle(b,d,c);}else{triangle(a,c,b);triangle(b,c,d);}
    }
  }
  for(var j=0;j<count;j++){
    final a=point(0,0,j),b=point(1,0,j),c=point(0,0,j+1),d=point(1,0,j+1);
    triangle(a,b,c);triangle(c,b,d);
    final e=point(0,3,j),f=point(1,3,j),g=point(0,3,j+1),h=point(1,3,j+1);
    triangle(e,g,f);triangle(g,h,f);
  }
  return PlatePart(name:'Adapter_${spec.first.diameter}_${spec.second.diameter}.stl',vertices:Float32List.fromList(values),
    unitScale:unit,width:maximum*2,depth:maximum*2,height:spec.length);
}
