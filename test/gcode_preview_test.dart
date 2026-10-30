import 'package:flutter_test/flutter_test.dart';
import 'package:print_optimizer/gcode_preview.dart';
import 'package:print_optimizer/printer_setup.dart';

void main(){
  const bed=PrinterBed(250,250,250);
  test('Layer paths use real extrusion deltas across retractions, resets and relative modes',(){
    final result=parseGcode((''';TIME:1234
;Filament used:0.123m
G90
M82
G92 E0
;LAYER:0
G0 X10 Y10 Z0.2
;TYPE:WALL-OUTER
G1 X20 Y10 E1
G1 E0.5
G0 X20 Y20
G1 E1
G1 X10 Y20 E2
;LAYER:1
G0 Z0.4
;TYPE:SUPPORT
G92 E0
M83
G1 X20 Y20 E0.2
G91
G1 X0 Y-10 E0.2
''',bed));
    expect(result.layers.length,2);expect(result.extrusionMoves,4);expect(result.outsideBed,isFalse);
    expect(result.layers[0].z,.2);expect(result.layers[1].z,.4);expect(result.seconds,1234);expect(result.filamentMetres,.123);
    final last=result.layers[1].segments;
    expect(last.sublist(last.length-5),[20,20,20,10,3]);
  });
  test('Outside-bed moves and unsupported arcs cannot appear as a valid preview',(){
    expect(parseGcode((';LAYER:0\nG1 X251 Y10 E1',bed)).outsideBed,isTrue);
    expect(()=>parseGcode((';LAYER:0\nG2 X10 Y10 E1',bed)),throwsFormatException);
    expect(()=>parseGcode((';LAYER:0\nG1 XNaN Y10 E1',bed)),throwsFormatException);
  });
}
