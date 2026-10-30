import 'dart:math' as math;
import 'dart:typed_data';

class SupportAssessment {
  const SupportAssessment(this.status, this.reason);
  final String status, reason;
}

// Conservative geometry hint in the file's orientation, never a slicer result.
// Work is bounded; unsupported topology must not be reported as support-free.
SupportAssessment assessSupports(Float32List vertices, {bool is3mf = false}) {
  const unknown = 'Im Slicer prüfen';
  if (is3mf) return const SupportAssessment(unknown,
    '3MF-Bauteiltransformationen und Druckplattenausrichtung werden noch nicht vollständig ausgewertet.');
  final count = vertices.length ~/ 9;
  if (count == 0 || vertices.length % 9 != 0 || count > 60000) {
    return const SupportAssessment(unknown, 'Für diese Modellgröße ist noch keine vollständige Überhangprüfung verfügbar.');
  }
  final parents = List<int>.generate(count, (i) => i);
  int root(int i) {
    while (parents[i] != i) { parents[i] = parents[parents[i]]; i = parents[i]; }
    return i;
  }
  final edges = <String, (int, String, String, int)>{};
  var valid = true, volume = 0.0, bottom = double.infinity;
  final normals = <(double, double, double)>[];
  String point(int offset) => '${(vertices[offset] * 10000000).round()},${(vertices[offset + 1] * 10000000).round()},${(vertices[offset + 2] * 10000000).round()}';
  for (var f = 0; f < count; f++) {
    final i = f * 9;
    for (var j = i; j < i + 9; j++) {
      if (!vertices[j].isFinite) return const SupportAssessment(unknown, 'Ungültige Modellkoordinaten.');
    }
    final ax = vertices[i], ay = vertices[i + 1], az = vertices[i + 2];
    final bx = vertices[i + 3], by = vertices[i + 4], bz = vertices[i + 5];
    final cx = vertices[i + 6], cy = vertices[i + 7], cz = vertices[i + 8];
    final nx = (by-ay)*(cz-az)-(bz-az)*(cy-ay);
    final ny = (bz-az)*(cx-ax)-(bx-ax)*(cz-az);
    final nz = (bx-ax)*(cy-ay)-(by-ay)*(cx-ax);
    final area = math.sqrt(nx*nx+ny*ny+nz*nz);
    if (area < 1e-12) valid = false;
    normals.add((nz, area, math.max(az, math.max(bz, cz))));
    volume += ax*(by*cz-bz*cy)+ay*(bz*cx-bx*cz)+az*(bx*cy-by*cx);
    bottom = math.min(bottom, math.min(az, math.min(bz, cz)));
    final points = [point(i), point(i+3), point(i+6)];
    for (var e = 0; e < 3; e++) {
      final a = points[e], b = points[(e+1)%3];
      final key = a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';
      final old = edges[key];
      if (old == null) { edges[key] = (f, a, b, 1); }
      else {
        if (old.$4 != 1 || old.$2 != b || old.$3 != a) valid = false;
        parents[root(f)] = root(old.$1);
        edges[key] = (old.$1, old.$2, old.$3, old.$4+1);
      }
    }
  }
  if (!valid || edges.values.any((e) => e.$4 != 2) || volume.abs() < 1e-10 ||
      List<int>.generate(count, root).toSet().length != 1) {
    return const SupportAssessment(unknown,
      'Offene, uneinheitlich orientierte oder mehrteilige Geometrie: Stützbedarf lässt sich hier nicht zuverlässig bestimmen.');
  }
  final sign = volume > 0 ? 1 : -1;
  final threshold = -math.sin(50 * math.pi / 180);
  final overhang = normals.any((n) => n.$3 > bottom + 1e-5 && sign*n.$1/n.$2 < threshold);
  return overhang
    ? const SupportAssessment('Stützen empfohlen',
        'Nach unten gerichtete Flächen mit mehr als 50° Überhang gegenüber der Senkrechten oberhalb der Grundfläche erkannt. Brücken und Stützbereiche im Slicer prüfen.')
    : const SupportAssessment('Voraussichtlich keine Stützen nötig',
        'Bei dieser Prüfung keine kritischen Überhänge über 50° erkannt. Kleine Details, Material und Druckprofil können das Ergebnis beeinflussen.');
}
