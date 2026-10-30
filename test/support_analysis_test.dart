import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:print_optimizer/support_analysis.dart';

import 'geometry_fixtures.dart';

void main() {
  test('Checks every face of a closed model equivalent to a binary STL over 30 MiB', () {
    final mesh = denseCube(240); // 691,200 triangles; binary STL size ~33 MiB.
    expect(84 + mesh.length ~/ 9 * 50, greaterThan(30*1024*1024));
    expect(assessSupports(mesh).status, 'Voraussichtlich keine Stützen nötig');
  }, timeout: const Timeout(Duration(minutes: 3)));
  test('Finds real overhangs beyond the old 60,000-face limit', () {
    final mesh = denseInvertedPyramid(110);
    expect(mesh.length ~/ 9, greaterThan(60000));
    expect(assessSupports(mesh).status, 'Stützen empfohlen');
  });
  test('Pyramid on its base excludes build plate contact; inverted pyramid needs support', () {
    expect(assessSupports(pyramid()).status, 'Voraussichtlich keine Stützen nötig');
    expect(assessSupports(pyramid(inverted: true)).status, 'Stützen empfohlen');
  });
  test('Global reversed winding has the same result', () {
    expect(assessSupports(pyramid(reverse: true)).status, assessSupports(pyramid()).status);
    expect(assessSupports(pyramid(inverted: true, reverse: true)).status, 'Stützen empfohlen');
  });
  test('Open, inconsistent, multiple shells and degenerate meshes remain unknown', () {
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
