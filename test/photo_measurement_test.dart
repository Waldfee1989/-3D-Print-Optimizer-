import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:print_optimizer/photo_measurement.dart';
void main(){
  test('Known reference scales another visible distance in the same image plane',(){
    final calibration=PhotoCalibration(const PhotoPoint(100,100),const PhotoPoint(300,100),35);
    expect(calibration.measure(const PhotoPoint(50,50),const PhotoPoint(350,50)),52.5);
    expect(PhotoCalibration(const PhotoPoint(0,0),const PhotoPoint(30,40),10).measure(const PhotoPoint(0,0),const PhotoPoint(60,80)),20);
  });
  test('Missing or degenerate reference cannot produce a measurement',(){
    expect(()=>PhotoCalibration(const PhotoPoint(0,0),const PhotoPoint(0,0),35),throwsFormatException);
    expect(()=>PhotoCalibration(const PhotoPoint(0,0),const PhotoPoint(20,0),0),throwsFormatException);
  });
  test('Edge assistance finds a nearby real image edge and preserves flat-area taps',(){
    final pixels=Uint8List(100*100*4);
    for(var y=0;y<100;y++)for(var x=0;x<100;x++){
      final at=(y*100+x)*4,value=x>=50?255:0;pixels[at]=pixels[at+1]=pixels[at+2]=value;pixels[at+3]=255;
    }
    expect(snapPhotoEdge(pixels,100,100,const PhotoPoint(47,50)).x,closeTo(50,1.5));
    final flat=snapPhotoEdge(pixels,100,100,const PhotoPoint(10,10));expect(flat.x,10);expect(flat.y,10);
  });
}
