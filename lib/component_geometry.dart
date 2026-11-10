import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart' show Offset;

import 'plate_geometry.dart';

enum ComponentShape { adapter, box, oval, contour }

extension ComponentShapeLabel on ComponentShape {
  String get label => switch (this) {
    ComponentShape.adapter => 'Runder Übergang / Adapter',
    ComponentShape.box => 'Eckig / Quader',
    ComponentShape.oval => 'Rund / ovaler Vollkörper',
    ComponentShape.contour => 'Andere Form / freie Kontur',
  };
}

/// A solid with a constant cross section. Contour coordinates may be in any
/// scale; only their proportions are used, the three confirmed dimensions rule.
class ComponentSpec {
  const ComponentSpec({
    required this.shape,
    required this.width,
    required this.depth,
    required this.height,
    this.contour = const [],
  });
  final ComponentShape shape;
  final double width, depth, height;
  final List<Offset> contour;

  String? validate() {
    if (shape == ComponentShape.adapter)
      return 'Für Übergänge den Adapter-Assistenten verwenden.';
    if ([width, depth, height].any((v) => !v.isFinite || v < .5 || v > 2000)) {
      return 'Alle drei Maße zwischen 0,5 und 2000 mm eintragen.';
    }
    if (shape != ComponentShape.contour) return null;
    if (contour.length < 3 || contour.length > 128)
      return 'Mindestens 3 und höchstens 128 Eckpunkte setzen.';
    if (contour.any((p) => !p.dx.isFinite || !p.dy.isFinite))
      return 'Ungültige Konturpunkte.';
    final points = _scaledContour(contour, width, depth);
    if (points == null) return 'Die Kontur braucht Breite und Länge.';
    for (var i = 0; i < points.length; i++) {
      if ((points[i] - points[(i + 1) % points.length]).distance < .001) {
        return 'Benachbarte Eckpunkte dürfen nicht aufeinanderliegen.';
      }
      for (var j = i + 1; j < points.length; j++) {
        if (j == i + 1 || (i == 0 && j == points.length - 1)) continue;
        if (_intersects(
          points[i],
          points[(i + 1) % points.length],
          points[j],
          points[(j + 1) % points.length],
        )) {
          return 'Die Kontur darf sich nicht kreuzen oder berühren.';
        }
      }
    }
    if (_area(points).abs() < .001)
      return 'Die Kontur muss eine Fläche umschließen.';
    return null;
  }
}

double _cross(Offset a, Offset b, Offset c) =>
    (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
double _area(List<Offset> p) {
  var area = 0.0;
  for (var i = 0; i < p.length; i++) {
    final b = p[(i + 1) % p.length];
    area += p[i].dx * b.dy - b.dx * p[i].dy;
  }
  return area / 2;
}

bool _intersects(Offset a, Offset b, Offset c, Offset d) {
  const eps = 1e-8;
  bool on(Offset p, Offset q, Offset r) =>
      _cross(p, q, r).abs() < eps &&
      r.dx >= math.min(p.dx, q.dx) - eps &&
      r.dx <= math.max(p.dx, q.dx) + eps &&
      r.dy >= math.min(p.dy, q.dy) - eps &&
      r.dy <= math.max(p.dy, q.dy) + eps;
  final c1 = _cross(a, b, c),
      c2 = _cross(a, b, d),
      c3 = _cross(c, d, a),
      c4 = _cross(c, d, b);
  return (c1 * c2 < 0 && c3 * c4 < 0) ||
      on(a, b, c) ||
      on(a, b, d) ||
      on(c, d, a) ||
      on(c, d, b);
}

List<Offset>? _scaledContour(List<Offset> p, double width, double depth) {
  final minX = p.map((p) => p.dx).reduce(math.min),
      maxX = p.map((p) => p.dx).reduce(math.max);
  final minY = p.map((p) => p.dy).reduce(math.min),
      maxY = p.map((p) => p.dy).reduce(math.max);
  if (maxX - minX < 1e-8 || maxY - minY < 1e-8) return null;
  return [
    for (final v in p)
      Offset(
        (v.dx - minX) / (maxX - minX) * width - width / 2,
        (v.dy - minY) / (maxY - minY) * depth - depth / 2,
      ),
  ];
}

PlatePart buildComponent(ComponentSpec spec) {
  final error = spec.validate();
  if (error != null) throw FormatException(error);
  var polygon = switch (spec.shape) {
    ComponentShape.box => [
      Offset(-spec.width / 2, -spec.depth / 2),
      Offset(spec.width / 2, -spec.depth / 2),
      Offset(spec.width / 2, spec.depth / 2),
      Offset(-spec.width / 2, spec.depth / 2),
    ],
    ComponentShape.oval => [
      for (var i = 0; i < 128; i++)
        Offset(
          spec.width / 2 * math.cos(i * 2 * math.pi / 128),
          spec.depth / 2 * math.sin(i * 2 * math.pi / 128),
        ),
    ],
    ComponentShape.contour => _scaledContour(
      spec.contour,
      spec.width,
      spec.depth,
    )!,
    ComponentShape.adapter => throw const FormatException(
      'Adapter-Assistenten verwenden.',
    ),
  };
  if (_area(polygon) < 0) polygon = polygon.reversed.toList();
  // Remove redundant points on straight edges before triangulating.
  var changed = true;
  while (changed && polygon.length > 3) {
    changed = false;
    for (var i = 0; i < polygon.length; i++) {
      if (_cross(
            polygon[(i + polygon.length - 1) % polygon.length],
            polygon[i],
            polygon[(i + 1) % polygon.length],
          ).abs() <
          1e-8) {
        polygon.removeAt(i);
        changed = true;
        break;
      }
    }
  }
  final remaining = List.generate(polygon.length, (i) => i),
      faces = <(int, int, int)>[];
  bool inside(Offset p, Offset a, Offset b, Offset c) =>
      _cross(a, b, p) >= -1e-8 &&
      _cross(b, c, p) >= -1e-8 &&
      _cross(c, a, p) >= -1e-8;
  while (remaining.length > 3) {
    var found = false;
    for (var i = 0; i < remaining.length; i++) {
      final a = remaining[(i + remaining.length - 1) % remaining.length],
          b = remaining[i],
          c = remaining[(i + 1) % remaining.length];
      if (_cross(polygon[a], polygon[b], polygon[c]) <= 1e-8) continue;
      if (remaining.any(
        (k) =>
            k != a &&
            k != b &&
            k != c &&
            inside(polygon[k], polygon[a], polygon[b], polygon[c]),
      ))
        continue;
      faces.add((a, b, c));
      remaining.removeAt(i);
      found = true;
      break;
    }
    if (!found)
      throw const FormatException(
        'Kontur konnte nicht geschlossen werden. Eckpunkte prüfen.',
      );
  }
  faces.add((remaining[0], remaining[1], remaining[2]));
  final scale =
      math.sqrt(
        spec.width * spec.width +
            spec.depth * spec.depth +
            spec.height * spec.height,
      ) /
      2;
  final values = <double>[];
  void point(int i, double z) =>
      values.addAll([polygon[i].dx / scale, polygon[i].dy / scale, z / scale]);
  void tri(int a, double za, int b, double zb, int c, double zc) {
    point(a, za);
    point(b, zb);
    point(c, zc);
  }

  final low = -spec.height / 2, high = spec.height / 2;
  for (final f in faces) {
    tri(f.$1, high, f.$2, high, f.$3, high);
    tri(f.$3, low, f.$2, low, f.$1, low);
  }
  for (var i = 0; i < polygon.length; i++) {
    final j = (i + 1) % polygon.length;
    tri(i, low, j, low, i, high);
    tri(j, low, j, high, i, high);
  }
  return PlatePart(
    name: 'Bauteil_${spec.shape.name}.stl',
    vertices: Float32List.fromList(values),
    unitScale: scale,
    width: spec.width,
    depth: spec.depth,
    height: spec.height,
  );
}
