import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:print_optimizer/component_geometry.dart';
import 'package:print_optimizer/plate_geometry.dart';

void checkSolid(PlatePart part, double expectedVolume) {
  final edges = <(String, String), int>{};
  var volume = 0.0;
  final v = part.vertices;
  String key(int i) =>
      [for (var j = 0; j < 3; j++) (v[i + j] * part.unitScale * 10000).round()]
          .join(',');
  for (var i = 0; i < v.length; i += 9) {
    final a = [v[i], v[i + 1], v[i + 2]],
        b = [v[i + 3], v[i + 4], v[i + 5]],
        c = [v[i + 6], v[i + 7], v[i + 8]];
    volume +=
        (a[0] * (b[1] * c[2] - b[2] * c[1]) +
            a[1] * (b[2] * c[0] - b[0] * c[2]) +
            a[2] * (b[0] * c[1] - b[1] * c[0])) /
        6 *
        math.pow(part.unitScale, 3);
    for (final pair in [(i, i + 3), (i + 3, i + 6), (i + 6, i)]) {
      final edge = (key(pair.$1), key(pair.$2));
      edges[edge] = (edges[edge] ?? 0) + 1;
    }
  }
  for (final edge in edges.keys)
    expect(
      edges[(edge.$2, edge.$1)],
      1,
      reason: 'Every edge has one opposite edge',
    );
  expect(volume, closeTo(expectedVolume, expectedVolume * .001));
  for (var axis = 0; axis < 3; axis++) {
    final positions = [
      for (var i = axis; i < v.length; i += 3) v[i] * part.unitScale,
    ];
    expect(
      positions.reduce(math.max) - positions.reduce(math.min),
      closeTo([part.width, part.depth, part.height][axis], .001),
    );
  }
}

void main() {
  test('Quader has exact dimensions, closed surface and outward winding', () {
    checkSolid(
      buildComponent(
        const ComponentSpec(
          shape: ComponentShape.box,
          width: 20,
          depth: 30,
          height: 5,
        ),
      ),
      3000,
    );
  });
  test('Oval uses independent axes and height', () {
    checkSolid(
      buildComponent(
        const ComponentSpec(
          shape: ComponentShape.oval,
          width: 20,
          depth: 40,
          height: 10,
        ),
      ),
      math.pi * 10 * 20 * 10,
    );
  });
  test('Concave L contour triangulates in either winding', () {
    const contour = [
      Offset(0, 0),
      Offset(1, 0),
      Offset(1, .5),
      Offset(.5, .5),
      Offset(.5, 1),
      Offset(0, 1),
    ];
    for (final points in [contour, contour.reversed.toList()]) {
      checkSolid(
        buildComponent(
          ComponentSpec(
            shape: ComponentShape.contour,
            width: 20,
            depth: 40,
            height: 5,
            contour: points,
          ),
        ),
        3000,
      );
    }
  });
  test('Collinear extra corners are removed without opening the solid', () {
    checkSolid(
      buildComponent(
        const ComponentSpec(
          shape: ComponentShape.contour,
          width: 20,
          depth: 30,
          height: 5,
          contour: [
            Offset(0, 0),
            Offset(.5, 0),
            Offset(1, 0),
            Offset(1, 1),
            Offset(0, 1),
          ],
        ),
      ),
      3000,
    );
  });
  test('Invalid dimensions and crossing or touching contours are rejected', () {
    for (final n in [double.nan, double.infinity, 0.0, -1.0, 2001.0]) {
      expect(
        () => buildComponent(
          ComponentSpec(
            shape: ComponentShape.box,
            width: n,
            depth: 20,
            height: 5,
          ),
        ),
        throwsFormatException,
      );
    }
    for (final points in [
      <Offset>[],
      [const Offset(0, 0), const Offset(1, 0)],
      [
        const Offset(0, 0),
        const Offset(1, 1),
        const Offset(0, 1),
        const Offset(1, 0),
      ],
      [
        const Offset(0, 0),
        const Offset(1, 0),
        const Offset(1, 1),
        const Offset(0, 0),
        const Offset(0, 1),
      ],
      [const Offset(0, 0), const Offset(0, 0), const Offset(1, 1)],
    ]) {
      expect(
        () => buildComponent(
          ComponentSpec(
            shape: ComponentShape.contour,
            width: 20,
            depth: 30,
            height: 5,
            contour: points,
          ),
        ),
        throwsFormatException,
      );
    }
  });
}
