import 'dart:math' as math;
import 'dart:typed_data';

class SupportAssessment {
  const SupportAssessment(this.status, this.reason, {this.overhangFaces,
    this.suggestedAxis = 0, this.overhangFraction = 0, this.suggestedFraction = 0, this.valid = false,this.candidateAreas,this.candidateContacts});
  final String status, reason;
  final Uint8List? overhangFaces;
  final int suggestedAxis;
  final double overhangFraction, suggestedFraction;
  final bool valid;
  final Float64List? candidateAreas,candidateContacts;
}

// Exact compact vertex IDs and sorted edge pairs replace the old string map.
// All faces are checked. Temporary numeric buffers scale linearly (about 52
// bytes/triangle peak beyond the render buffer); no 60,000-face cutoff or sampling.
// Caller runs this on the import worker, not the UI isolate.
SupportAssessment assessSupports(Float32List vertices, {bool is3mf = false}) {
  const unknown = 'Im Slicer prüfen';
  const invalid = SupportAssessment(unknown,
    'Offene, uneinheitlich orientierte oder mehrteilige Geometrie: Stützbedarf im Slicer prüfen.');
  if (is3mf) return const SupportAssessment(unknown,
    '3MF-Bauteiltransformationen und Druckplattenausrichtung werden noch nicht vollständig ausgewertet.');
  final count = vertices.length ~/ 9;
  if (count == 0 || vertices.length % 9 != 0 || count > 2500000) {
    return const SupportAssessment(unknown, 'Modell außerhalb der unterstützten Importgröße.');
  }
  var volume = 0.0;
  final minima = Float64List(3)..fillRange(0,3,double.infinity);
  final maxima = Float64List(3)..fillRange(0,3,double.negativeInfinity);
  for (var i = 0; i < vertices.length; i += 9) {
    for (var j = i; j < i+9; j++) {
      if (!vertices[j].isFinite) return const SupportAssessment(unknown, 'Ungültige Modellkoordinaten.');
    }
    final ax = vertices[i], ay = vertices[i+1], az = vertices[i+2];
    final bx = vertices[i+3], by = vertices[i+4], bz = vertices[i+5];
    final cx = vertices[i+6], cy = vertices[i+7], cz = vertices[i+8];
    final nx = (by-ay)*(cz-az)-(bz-az)*(cy-ay);
    final ny = (bz-az)*(cx-ax)-(bx-ax)*(cz-az);
    final nz = (bx-ax)*(cy-ay)-(by-ay)*(cx-ax);
    if (nx*nx+ny*ny+nz*nz < 1e-24) return invalid;
    volume += ax*(by*cz-bz*cy)+ay*(bz*cx-bx*cz)+az*(bx*cy-by*cx);
    for (var v = i; v < i+9; v += 3) {
      for (var k = 0; k < 3; k++) {
        minima[k] = math.min(minima[k],vertices[v+k]);
        maxima[k] = math.max(maxima[k],vertices[v+k]);
      }
    }
  }
  if (volume.abs() < 1e-10) return invalid;
  final ids = _vertexIds(vertices);
  final pointCount = vertices.length ~/ 3;
  final edgeCount = count*3;
  if (edgeCount.isOdd) return invalid;
  final codes = Uint64List(edgeCount);
  final faces = Int32List(edgeCount);
  for (var f = 0; f < count; f++) {
    for (var e = 0; e < 3; e++) {
      final a = ids[f*3+e], b = ids[f*3+(e+1)%3];
      final low = math.min(a,b), high = math.max(a,b);
      // Vertex IDs are bounded by 7.5 million, so this fits exactly in 47 bits.
      codes[f*3+e] = (low*pointCount+high)*2+(a < b ? 0 : 1);
      faces[f*3+e] = f;
    }
  }
  _sortPairs(codes, faces);
  final parents = Int32List(count);
  for (var i = 0; i < count; i++) { parents[i] = i; }
  int root(int i) {
    while (parents[i] != i) { parents[i] = parents[parents[i]]; i = parents[i]; }
    return i;
  }
  for (var i = 0; i < edgeCount; i += 2) {
    final key = codes[i] ~/ 2;
    if (codes[i].isOdd || codes[i+1] != codes[i]+1 ||
        (i+2 < edgeCount && codes[i+2] ~/ 2 == key)) return invalid;
    parents[root(faces[i])] = root(faces[i+1]);
  }
  final firstRoot = root(0);
  for (var i = 1; i < count; i++) { if (root(i) != firstRoot) return invalid; }
  final sign = volume > 0 ? 1 : -1;
  final threshold = -math.sin(50*math.pi/180);
  final areas = Float64List(6), contact = Float64List(6);
  final flags = Uint8List(count);
  var totalArea = 0.0;
  for (var i = 0; i < vertices.length; i += 9) {
    final ax = vertices[i], ay = vertices[i+1], az = vertices[i+2];
    final bx = vertices[i+3], by = vertices[i+4], bz = vertices[i+5];
    final cx = vertices[i+6], cy = vertices[i+7], cz = vertices[i+8];
    final nx = (by-ay)*(cz-az)-(bz-az)*(cy-ay);
    final ny = (bz-az)*(cx-ax)-(bx-ax)*(cz-az);
    final nz = (bx-ax)*(cy-ay)-(by-ay)*(cx-ax);
    final area = math.sqrt(nx*nx+ny*ny+nz*nz);
    totalArea += area;
    for (var k = 0; k < 3; k++) {
      // Candidate order: +Z, -Z, +X, -X, +Y, -Y pointing upward.
      final coordinate = k == 0 ? 2 : k-1;
      final normal = coordinate == 0 ? nx : coordinate == 1 ? ny : nz;
      final lo = math.min(vertices[i+coordinate],math.min(vertices[i+3+coordinate],vertices[i+6+coordinate]));
      final hi = math.max(vertices[i+coordinate],math.max(vertices[i+3+coordinate],vertices[i+6+coordinate]));
      for (var direction = 0; direction < 2; direction++) {
        final candidate = k*2+direction;
        final onFloor = direction == 0 ? hi <= minima[coordinate]+1e-5 : lo >= maxima[coordinate]-1e-5;
        if (onFloor) { contact[candidate] += area; continue; }
        final component = direction == 0 ? normal : -normal;
        if (sign*component/area < threshold) {
          areas[candidate] += area;
          if (candidate == 0) flags[i~/9] = 1;
        }
      }
    }
  }
  var best = 0;
  for (var k = 1; k < 6; k++) {
    if (areas[k] < areas[best]-totalArea*1e-6 ||
        ((areas[k]-areas[best]).abs() <= totalArea*1e-6 && contact[k] > contact[best]+totalArea*1e-6)) best = k;
  }
  final hasOverhang = areas[0] > 0;
  return SupportAssessment(hasOverhang ? 'Stützen empfohlen' : 'Voraussichtlich keine Stützen nötig',
    hasOverhang ? 'Überhänge über 50° oberhalb der Grundfläche erkannt. Brücken und Stützbereiche im Slicer prüfen.'
      : 'Keine kritischen Überhänge über 50° erkannt. Material, Brücken und kleine Details im Slicer prüfen.',
    overhangFaces: flags, suggestedAxis: best, valid: true,candidateAreas: areas,candidateContacts: contact,
    overhangFraction: areas[0]/totalArea, suggestedFraction: areas[best]/totalArea);

}

Int32List _vertexIds(Float32List vertices) {
  final n = vertices.length ~/ 3;
  final order = Int32List(n);
  for (var i = 0; i < n; i++) { order[i] = i; }
  int compare(int a, int b) {
    for (var k = 0; k < 3; k++) {
      final av = vertices[a*3+k], bv = vertices[b*3+k];
      if (av < bv) return -1;
      if (av > bv) return 1;
    }
    return 0;
  }
  void sort(int left, int right) {
    while (left < right) {
      var i = left, j = right;
      final pivot = order[(left+right)~/2];
      while (i <= j) {
        while (compare(order[i], pivot) < 0) { i++; }
        while (compare(order[j], pivot) > 0) { j--; }
        if (i <= j) {
          final old = order[i]; order[i] = order[j]; order[j] = old; i++; j--;
        }
      }
      // Recurse into the smaller partition: logarithmic stack bound.
      if (j-left < right-i) { if (left < j) sort(left,j); left = i; }
      else { if (i < right) sort(i,right); right = j; }
    }
  }
  sort(0,n-1);
  final ids = Int32List(n);
  var next = 0;
  for (var i = 0; i < n; i++) {
    if (i > 0 && compare(order[i-1],order[i]) != 0) next++;
    ids[order[i]] = next;
  }
  return ids;
}

void _sortPairs(Uint64List codes, Int32List faces) {
  void sort(int left, int right) {
    while (left < right) {
      var i = left, j = right;
      final pivot = codes[(left+right)~/2];
      while (i <= j) {
        while (codes[i] < pivot) { i++; }
        while (codes[j] > pivot) { j--; }
        if (i <= j) {
          final code = codes[i]; codes[i] = codes[j]; codes[j] = code;
          final face = faces[i]; faces[i] = faces[j]; faces[j] = face;
          i++; j--;
        }
      }
      if (j-left < right-i) { if (left < j) sort(left,j); left = i; }
      else { if (i < right) sort(i,right); right = j; }
    }
  }
  sort(0,codes.length-1);
}
