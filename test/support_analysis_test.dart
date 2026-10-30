import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:print_optimizer/support_analysis.dart';

Float32List pyramid({bool inverted = false, bool reverse = false}) {
  final z = inverted ? .3 : 0.0;
  final points = <List<double>>[[-1,-1,z], [1,-1,z], [1,1,z], [-1,1,z], [0,0,inverted ? 0 : 1]];
  final faces = [[0,2,1],[0,3,2],[0,1,4],[1,2,4],[2,3,4],[3,0,4]];
  return Float32List.fromList([for (final f in faces)
    for (final i in reverse ? f.reversed : f) ...points[i]]);
}

void main() {
  test('Pyramid on its base excludes build plate contact; inverted pyramid needs support', () {
    expect(assessSupports(pyramid()).status, 'Voraussichtlich keine Stützen nötig');
    expect(assessSupports(pyramid(inverted: true)).status, 'Stützen empfohlen');
  });
  test('Global reversed winding has the same result', () {
    expect(assessSupports(pyramid(reverse: true)).status, assessSupports(pyramid()).status);
    expect(assessSupports(pyramid(inverted: true, reverse: true)).status, 'Stützen empfohlen');
  });
  test('Open, inconsistent, multiple shells and oversized meshes remain unknown', () {
    final v = pyramid();
    expect(assessSupports(Float32List.fromList(v.sublist(0, v.length-9))).status, 'Im Slicer prüfen');
    final broken = Float32List.fromList(v);
    broken.setRange(0, 9, [...v.sublist(6,9), ...v.sublist(3,6), ...v.sublist(0,3)]);
    expect(assessSupports(broken).status, 'Im Slicer prüfen');
    final moved = [for (var i = 0; i < v.length; i++) v[i] + (i % 3 == 0 ? 5 : 0)];
    expect(assessSupports(Float32List.fromList([...v, ...moved])).status, 'Im Slicer prüfen');
    expect(assessSupports(Float32List(60001*9)).status, 'Im Slicer prüfen');
    expect(assessSupports(v, is3mf: true).status, 'Im Slicer prüfen');
  });
  test('Horizontal top face above build plate is not mistaken for a downward face', () {
    // Closed cube, two triangles per side; reversed winding is accepted too.
    const p = [[-1.0,-1.0,0.0],[1.0,-1.0,0.0],[1.0,1.0,0.0],[-1.0,1.0,0.0],
      [-1.0,-1.0,1.0],[1.0,-1.0,1.0],[1.0,1.0,1.0],[-1.0,1.0,1.0]];
    const faces = [[0,2,1],[0,3,2],[4,5,6],[4,6,7],[0,1,5],[0,5,4],
      [1,2,6],[1,6,5],[2,3,7],[2,7,6],[3,0,4],[3,4,7]];
    final cube = Float32List.fromList([for (final f in faces) for (final i in f) ...p[i]]);
    expect(assessSupports(cube).status, 'Voraussichtlich keine Stützen nötig');
  });
}
