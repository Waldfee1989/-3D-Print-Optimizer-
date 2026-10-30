import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'print_geometry.dart';
import 'support_analysis.dart';
import 'printer_setup.dart';

class PlatePart {
  const PlatePart({required this.name,required this.vertices,required this.unitScale,
    required this.width,required this.depth,required this.height});
  final String name;
  final Float32List vertices; // Centered normalized coordinates, all triangles.
  final double unitScale, width, depth, height; // Original dimensions in mm.
}
class PlatePlacement {
  const PlatePlacement({required this.id,required this.part,required this.x,required this.y,
    this.scale = 1,this.turns = 0});
  final String id;
  final PlatePart part;
  final double x,y,scale;
  final int turns;
  double get width => (turns.isOdd ? part.depth : part.width)*scale;
  double get depth => (turns.isOdd ? part.width : part.depth)*scale;
  Rect get bounds => Rect.fromCenter(center: Offset(x,y),width: width,height: depth);
  PlatePlacement copy({double? x,double? y,double? scale,int? turns}) => PlatePlacement(
    id: id,part: part,x: x ?? this.x,y: y ?? this.y,scale: scale ?? this.scale,turns: turns ?? this.turns);
  bool fits(double w,double d,[double h = double.infinity]) => bounds.left >= -1e-6 && bounds.bottom <= d+1e-6 &&
    bounds.top >= -1e-6 && bounds.right <= w+1e-6 && part.height*scale <= h+1e-6;
}

PlatePlacement placeNextPart(PlatePart part,List<PlatePlacement> existing,double width,double depth,String id,{double scale = 1,int turns = 0}) {
  final original = PlatePlacement(id: id,part: part,x: 0,y: 0,scale: scale,turns: turns);
  final xs = <double>[5,for (final p in existing) p.bounds.right+5]..sort();
  final ys = <double>[5,for (final p in existing) p.bounds.bottom+5]..sort();
  for (final turn in [turns,(turns+1)%4]) {
    final prototype = original.copy(turns: turn);
    for (final y in ys) {
      for (final x in xs) {
        final next = prototype.copy(x: x+prototype.width/2,y: y+prototype.depth/2);
        if (next.fits(width,depth) && existing.every((p) => !next.bounds.inflate(2).overlaps(p.bounds))) return next;
      }
    }
  }
  return original.copy(x: width/2,y: depth/2);
}

(List<PlatePlacement>,int) autoOrientPlate((List<PlatePlacement>,double,double,double) request) {
  final output = <PlatePlacement>[];
  var unknown = 0;
  for (final placed in request.$1) {
    var part = placed.part;
    var turns = 0;
    final assessment = assessSupports(part.vertices);
    if (!assessment.valid) { unknown++; turns = placed.turns; }
    else {
      final axis = fittingPrintOrientation(part.vertices,assessment,part.unitScale*placed.scale,PrinterBed(request.$2,request.$3,request.$4));
      if (axis == null) { unknown++; output.add(placeNextPart(part,output,request.$2,request.$3,placed.id,scale: placed.scale,turns: placed.turns)); continue; }
      final v = rotatePrintVertices(part.vertices,axis);
      var minX = double.infinity,minY = double.infinity,minZ = double.infinity;
      var maxX = double.negativeInfinity,maxY = double.negativeInfinity,maxZ = double.negativeInfinity;
      for (var i = 0; i < v.length; i += 3) {
        minX = math.min(minX,v[i]); maxX = math.max(maxX,v[i]);
        minY = math.min(minY,v[i+1]); maxY = math.max(maxY,v[i+1]);
        minZ = math.min(minZ,v[i+2]); maxZ = math.max(maxZ,v[i+2]);
      }
      part = PlatePart(name: part.name,vertices: v,unitScale: part.unitScale,
        width: (maxX-minX)*part.unitScale,depth: (maxY-minY)*part.unitScale,height: (maxZ-minZ)*part.unitScale);
    }
    output.add(placeNextPart(part,output,request.$2,request.$3,placed.id,scale: placed.scale,turns: turns));
  }
  return (output,unknown);
}

Uint8List encodePlateStl(List<PlatePlacement> placements) {
  final count = placements.fold<int>(0,(a,p) => a+p.part.vertices.length~/9);
  if (count == 0 || 84+count*50 > 100*1024*1024) throw const FormatException('Gemeinsame STL ist größer als 100 MB oder leer.');
  final bytes = Uint8List(84+count*50);
  final data = ByteData.sublistView(bytes);
  const label = '3D Print Optimizer - Druckplatte - mm';
  bytes.setRange(0,label.length,label.codeUnits); data.setUint32(80,count,Endian.little);
  var f = 0;
  for (final placed in placements) {
    final v = placed.part.vertices;
    if (v.length % 9 != 0 || !placed.scale.isFinite || placed.scale <= 0 ||
        !placed.x.isFinite || !placed.y.isFinite || !placed.part.unitScale.isFinite || placed.part.unitScale <= 0) {
      throw const FormatException('Ungültige Teileanordnung.');
    }
    var floor = double.infinity;
    for (var i = 2; i < v.length; i += 3) { floor = math.min(floor,v[i]); }
    final scale = placed.part.unitScale*placed.scale;
    final angle = placed.turns*math.pi/2, c = math.cos(angle), s = math.sin(angle);
    for (var i = 0; i < v.length; i += 9) {
      final at = 84+f++*50;
      for (var k = 0; k < 9; k += 3) {
        final x = (v[i+k]*c-v[i+k+1]*s)*scale+placed.x;
        final y = (v[i+k]*s+v[i+k+1]*c)*scale+placed.y;
        final z = (v[i+k+2]-floor)*scale;
        for (final entry in [(0,x),(4,y),(8,z)]) {
          if (!entry.$2.isFinite || entry.$2.abs() > 3.402823466e38) throw const FormatException('Ungültige Exportkoordinaten.');
          data.setFloat32(at+12+k*4+entry.$1,entry.$2,Endian.little);
        }
      }
      // Zero normals are legal in STL; slicers derive them from the winding.
    }
  }
  return bytes;
}

