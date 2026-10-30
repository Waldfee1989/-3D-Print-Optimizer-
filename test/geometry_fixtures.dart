import 'dart:typed_data';

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

