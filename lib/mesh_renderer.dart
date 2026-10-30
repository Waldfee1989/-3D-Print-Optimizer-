import 'dart:math' as math;
import 'dart:typed_data';

// Pure Dart worker: every triangle participates in the depth test. Run off the
// UI isolate so large meshes do not block gestures or navigation.
class MeshRenderRequest {
  const MeshRenderRequest(
    this.vertices,
    this.width,
    this.height,
    this.angleX,
    this.angleY,
    this.zoom, {this.overhangFaces}
  );

  final Float32List vertices; // Normalized triangle coordinates, nine per face.
  final int width, height;
  final double angleX, angleY, zoom;
  final Uint8List? overhangFaces;
}

Uint8List renderMesh(MeshRenderRequest request) {
  final width = request.width, height = request.height;
  final pixels = Uint8List(width * height * 4);
  final depth = Float64List(width * height)
    ..fillRange(0, width * height, double.negativeInfinity);
  final x = request.angleX * math.pi / 180;
  final y = request.angleY * math.pi / 180;
  final sx = math.sin(x), cx = math.cos(x);
  final sy = math.sin(y), cy = math.cos(y);
  final scale = math.min(width, height) * .425 * request.zoom;
  final source = request.vertices;
  final transformed = Float64List(9);

  for (var face = 0; face < source.length; face += 9) {
    for (var vertex = 0; vertex < 9; vertex += 3) {
      final a = source[face + vertex];
      final b = source[face + vertex + 1];
      final c = source[face + vertex + 2];
      final rx = cy * a + sy * c;
      final rz = -sy * a + cy * c;
      transformed[vertex] = rx;
      transformed[vertex + 1] = cx * b - sx * rz;
      transformed[vertex + 2] = sx * b + cx * rz;
    }
    final ax = width / 2 + transformed[0] * scale;
    final ay = height / 2 - transformed[1] * scale;
    final bx = width / 2 + transformed[3] * scale;
    final by = height / 2 - transformed[4] * scale;
    final cxScreen = width / 2 + transformed[6] * scale;
    final cyScreen = height / 2 - transformed[7] * scale;
    final area = (bx - ax) * (cyScreen - ay) - (by - ay) * (cxScreen - ax);
    if (area.abs() < 1e-10) continue;
    final left = math.max(0, math.min(ax, math.min(bx, cxScreen)).floor());
    final right = math.min(
      width - 1,
      math.max(ax, math.max(bx, cxScreen)).ceil(),
    );
    final top = math.max(0, math.min(ay, math.min(by, cyScreen)).floor());
    final bottom = math.min(
      height - 1,
      math.max(ay, math.max(by, cyScreen)).ceil(),
    );

    final ux = transformed[3] - transformed[0];
    final uy = transformed[4] - transformed[1];
    final uz = transformed[5] - transformed[2];
    final vx = transformed[6] - transformed[0];
    final vy = transformed[7] - transformed[1];
    final vz = transformed[8] - transformed[2];
    var nx = uy * vz - uz * vy;
    var ny = uz * vx - ux * vz;
    var nz = ux * vy - uy * vx;
    final length = math.sqrt(nx * nx + ny * ny + nz * nz);
    if (length < 1e-15) continue;
    // Show both sides, including files with inconsistent triangle winding.
    final direction = nz < 0 ? -1.0 : 1.0;
    nx = nx / length * direction;
    ny = ny / length * direction;
    nz = nz / length * direction;
    final light =
        .3 + .7 * math.max(0.0, nx * -.35 + ny * .45 + nz * .8215838363);
    final flags = request.overhangFaces;
    final critical = flags != null && face~/9 < flags.length && flags[face~/9] != 0;
    final red = ((critical ? 255 : 130) * light).round();
    final green = ((critical ? 82 : 184) * light).round();
    final blue = ((critical ? 90 : 247) * light).round();

    for (var py = top; py <= bottom; py++) {
      for (var px = left; px <= right; px++) {
        final dx = px + .5 - ax, dy = py + .5 - ay;
        final b = (dx * (cyScreen - ay) - dy * (cxScreen - ax)) / area;
        final c = ((bx - ax) * dy - (by - ay) * dx) / area;
        final a = 1 - b - c;
        // Small tolerance prevents cracks along shared triangle edges.
        if (a < -1e-9 || b < -1e-9 || c < -1e-9) continue;
        final z = a * transformed[2] + b * transformed[5] + c * transformed[8];
        final index = py * width + px;
        if (z <= depth[index]) continue;
        depth[index] = z;
        final offset = index * 4;
        pixels[offset] = red;
        pixels[offset + 1] = green;
        pixels[offset + 2] = blue;
        pixels[offset + 3] = 255;
      }
    }
  }
  return pixels;
}

