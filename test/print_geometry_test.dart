import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:print_optimizer/print_geometry.dart';
import 'package:print_optimizer/support_analysis.dart';
import 'package:print_optimizer/mesh_renderer.dart';
import 'geometry_fixtures.dart';

void main() {
  test('Critical faces are flagged and a better candidate removes the inverted pyramid overhangs', () {
    final v = pyramid(inverted: true);
    final a = assessSupports(v);
    expect(a.valid,isTrue);
    expect(a.overhangFaces!.any((f) => f == 1),isTrue);
    expect(a.suggestedAxis,isNot(0));
    final result = orientPrintModel((v,a.suggestedAxis));
    expect(result.$2.overhangFraction,lessThan(a.overhangFraction));
    expect(result.$2.status,'Voraussichtlich keine Stützen nötig');
    expect(v,orderedEquals(pyramid(inverted: true)));
  });
  test('Marked faces render red without changing the depth/alpha mask', () {
    final v = pyramid(inverted: true);
    final flags = assessSupports(v).overhangFaces;
    final plain = renderMesh(MeshRenderRequest(v,100,100,180,0,1));
    final marked = renderMesh(MeshRenderRequest(v,100,100,180,0,1,overhangFaces: flags));
    var red = 0;
    for (var i = 0; i < plain.length; i += 4) {
      expect(marked[i+3],plain[i+3]);
      if (marked[i+3] != 0 && marked[i] > marked[i+2]) red++;
    }
    expect(red,greaterThan(0));
  });
  test('Scaled STL preserves triangles, puts bottom at zero and writes actual dimensions', () {
    final source = pyramid();
    final bytes = encodePrintStl((source,20.0));
    final data = ByteData.sublistView(bytes);
    expect(data.getUint32(80,Endian.little),6);
    var minX = double.infinity,maxX = double.negativeInfinity;
    var minZ = double.infinity,maxZ = double.negativeInfinity;
    for (var f = 0; f < 6; f++) {
      for (var k = 0; k < 3; k++) {
        final at = 84+f*50+12+k*12;
        final x = data.getFloat32(at,Endian.little),z = data.getFloat32(at+8,Endian.little);
        if (x < minX) minX = x; if (x > maxX) maxX = x;
        if (z < minZ) minZ = z; if (z > maxZ) maxZ = z;
      }
    }
    expect(maxX-minX,closeTo(40,1e-5));
    expect(maxZ-minZ,closeTo(20,1e-5));
    expect(minZ,0);
    expect(bytes.length,84+6*50);
  });
  test('Pose STL can be re-imported to give the same support result', () {
    final source = pyramid(inverted: true);
    final initial = assessSupports(source);
    final posed = rotatePrintVertices(source,initial.suggestedAxis);
    final bytes = encodePrintStl((posed,10));
    final data = ByteData.sublistView(bytes), restored = Float32List(posed.length);
    for (var f = 0; f < posed.length~/9; f++) {
      for (var k = 0; k < 9; k++) restored[f*9+k] = data.getFloat32(84+f*50+12+k*4,Endian.little);
    }
    expect(assessSupports(restored).status,assessSupports(posed).status);
  });
  test('Unknown topology does not pretend to have a safe pose or critical mask', () {
    final a = assessSupports(Float32List.fromList([0,0,0,1,0,0,0,1,0]));
    expect(a.valid,isFalse); expect(a.overhangFaces,isNull);
    expect(() => encodePrintStl((pyramid(),double.infinity)),throwsFormatException);
  });
}
