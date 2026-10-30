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

Float32List denseCube(int n) {
  const p = [[-1,-1,-1],[1,-1,-1],[1,1,-1],[-1,1,-1],[-1,-1,1],[1,-1,1],[1,1,1],[-1,1,1]];
  const quads = [[0,3,2,1],[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]];
  final result = Float32List(6*n*n*2*9);
  var at = 0;
  for (final q in quads) {
    void point(int i, int j) {
      for (var k = 0; k < 3; k++) {
        result[at++] = (p[q[0]][k]*n+(p[q[1]][k]-p[q[0]][k])*i+(p[q[3]][k]-p[q[0]][k])*j)/n;
      }
    }
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        point(i,j); point(i+1,j); point(i+1,j+1);
        point(i,j); point(i+1,j+1); point(i,j+1);
      }
    }
  }
  return result;
}

Float32List denseInvertedPyramid(int n) {
  final coarse = pyramid(inverted: true);
  final result = Float32List(6*n*n*9);
  var at = 0;
  for (var f = 0; f < 6; f++) {
    void point(int i, int j) {
      for (var k = 0; k < 3; k++) {
        final value = (coarse[f*9+k]*(n-i-j)+coarse[f*9+3+k]*i+coarse[f*9+6+k]*j)/n;
        result[at++] = (value*1000000).round()/1000000;
      }
    }
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n-i; j++) {
        point(i,j); point(i+1,j); point(i,j+1);
        if (i+j < n-1) { point(i+1,j); point(i+1,j+1); point(i,j+1); }
      }
    }
  }
  return result;
}

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
