import 'dart:math' as math;
import 'dart:typed_data';

class PhotoPoint {
  const PhotoPoint(this.x,this.y);final double x,y;
}
double photoDistance(PhotoPoint a,PhotoPoint b)=>math.sqrt(math.pow(a.x-b.x,2)+math.pow(a.y-b.y,2));
class PhotoCalibration {
  PhotoCalibration(this.first,this.second,this.millimetres){
    if(!millimetres.isFinite||millimetres<=0||millimetres>100000||!photoDistance(first,second).isFinite||photoDistance(first,second)<10)throw const FormatException('Gültiges Referenzmaß und ausreichend weit entfernte Punkte wählen.');
  }
  final PhotoPoint first,second;final double millimetres;
  double measure(PhotoPoint a,PhotoPoint b){
    if([a.x,a.y,b.x,b.y].any((v)=>!v.isFinite))throw const FormatException('Ungültige Bildpunkte.');
    return photoDistance(a,b)/photoDistance(first,second)*millimetres;
  }
}
// Local edge assistance around the user's tap; no image leaves the device.
PhotoPoint snapPhotoEdge(Uint8List rgba,int width,int height,PhotoPoint point){
  if(width<3||height<3||rgba.length!=width*height*4)return point;
  final px=point.x.round().clamp(1,width-2).toInt(),py=point.y.round().clamp(1,height-2).toInt();
  double grey(int x,int y){final at=(y*width+x)*4;return(rgba[at]*299+rgba[at+1]*587+rgba[at+2]*114)/1000;}
  var best=0.0,result=point;
  for(var y=math.max(1,py-8);y<=math.min(height-2,py+8);y++)for(var x=math.max(1,px-8);x<=math.min(width-2,px+8);x++){
    final gx=-grey(x-1,y-1)+grey(x+1,y-1)-2*grey(x-1,y)+2*grey(x+1,y)-grey(x-1,y+1)+grey(x+1,y+1);
    final gy=-grey(x-1,y-1)-2*grey(x,y-1)-grey(x+1,y-1)+grey(x-1,y+1)+2*grey(x,y+1)+grey(x+1,y+1);
    final strength=math.sqrt(gx*gx+gy*gy);if(strength<50)continue;
    final score=strength/(1+((x-point.x)*(x-point.x)+(y-point.y)*(y-point.y))/16);
    if(score>best){best=score;result=PhotoPoint(x.toDouble(),y.toDouble());}
  }
  return result;
}
