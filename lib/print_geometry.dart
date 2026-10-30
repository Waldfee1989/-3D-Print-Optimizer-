import 'dart:math' as math;
import 'dart:typed_data';
import 'support_analysis.dart';

const printOrientationNames = [
  'Wie in der Datei', '180° um X gedreht', '−90° um Y gedreht',
  '90° um Y gedreht', '90° um X gedreht', '−90° um X gedreht',
];

Float32List rotatePrintVertices(Float32List source, int axis) {
  if (axis < 0 || axis > 5 || source.length % 3 != 0) throw const FormatException('Ungültige Drucklage.');
  final out = Float32List(source.length);
  for (var i = 0; i < source.length; i += 3) {
    final x = source[i], y = source[i+1], z = source[i+2];
    final p = switch(axis) {
      1 => (x,-y,-z), 2 => (-z,y,x), 3 => (z,y,-x),
      4 => (x,-z,y), 5 => (x,z,-y), _ => (x,y,z),
    };
    out[i] = p.$1; out[i+1] = p.$2; out[i+2] = p.$3;
  }
  return out;
}

(Float32List, SupportAssessment, (double,double,double)) orientPrintModel((Float32List,int) request) {
  final vertices = rotatePrintVertices(request.$1,request.$2);
  var minX = double.infinity,minY = double.infinity,minZ = double.infinity;
  var maxX = double.negativeInfinity,maxY = double.negativeInfinity,maxZ = double.negativeInfinity;
  for (var i = 0; i < vertices.length; i += 3) {
    minX = math.min(minX,vertices[i]); maxX = math.max(maxX,vertices[i]);
    minY = math.min(minY,vertices[i+1]); maxY = math.max(maxY,vertices[i+1]);
    minZ = math.min(minZ,vertices[i+2]); maxZ = math.max(maxZ,vertices[i+2]);
  }
  return (vertices,assessSupports(vertices),(maxX-minX,maxY-minY,maxZ-minZ));
}

// A new geometric STL, centered in XY and resting at Z=0. The source file is
// never overwritten. 3MF colors/material assignments cannot be stored in STL.
Uint8List encodePrintStl((Float32List,double) request) {
  final vertices = request.$1, scale = request.$2;
  if (vertices.isEmpty || vertices.length % 9 != 0 || !scale.isFinite || scale <= 0) {
    throw const FormatException('Ungültige Exportgeometrie.');
  }
  final count = vertices.length ~/ 9;
  if (count > 2500000) throw const FormatException('Exportmodell zu groß.');
  var floor = double.infinity;
  for (var i = 2; i < vertices.length; i += 3) { floor = math.min(floor,vertices[i]); }
  final bytes = Uint8List(84+count*50);
  final data = ByteData.sublistView(bytes);
  const header = '3D Print Optimizer - Drucklage - mm';
  bytes.setRange(0,header.length,header.codeUnits);
  data.setUint32(80,count,Endian.little);
  for (var f = 0; f < count; f++) {
    final i = f*9, at = 84+f*50;
    final ux = vertices[i+3]-vertices[i], uy = vertices[i+4]-vertices[i+1], uz = vertices[i+5]-vertices[i+2];
    final vx = vertices[i+6]-vertices[i], vy = vertices[i+7]-vertices[i+1], vz = vertices[i+8]-vertices[i+2];
    final nx = uy*vz-uz*vy, ny = uz*vx-ux*vz, nz = ux*vy-uy*vx;
    final length = math.sqrt(nx*nx+ny*ny+nz*nz);
    for (var k = 0; k < 3; k++) {
      final normal = k == 0 ? nx : k == 1 ? ny : nz;
      data.setFloat32(at+k*4,length > 0 ? normal/length : 0,Endian.little);
    }
    for (var k = 0; k < 9; k++) {
      final value = (vertices[i+k]-(k%3 == 2 ? floor : 0))*scale;
      if (!value.isFinite || value.abs() > 3.402823466e38) throw const FormatException('Ungültige Exportkoordinaten.');
      data.setFloat32(at+12+k*4,value,Endian.little);
    }
  }
  return bytes;
}
