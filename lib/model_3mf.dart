import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

// Core build/component transforms and production part references:
// https://github.com/3MFConsortium/spec_core
// https://github.com/3MFConsortium/spec_production
Float64List readThreeMfTriangles(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes, verify: true);
  final files = <String, ArchiveFile>{};
  var expandedSize = 0;
  for (final file in archive.files.where((f) => f.isFile)) {
    expandedSize += file.size;
    if (expandedSize > 512*1024*1024) throw const FormatException('Entpackte 3MF-Datei ist zu groß.');
    files[_partPath('',file.name)] = file;
  }
  final documents = <String, XmlElement>{};
  final objectMaps = <String, Map<int,XmlElement>>{};
  XmlElement model(String path) => documents.putIfAbsent(path, () {
    final file = files[path];
    if (file == null) throw const FormatException('Referenzierter 3MF-Modellteil fehlt.');
    final data = file.content;
    if (data is! List<int>) throw const FormatException('3MF-Modellteil nicht lesbar.');
    final root = XmlDocument.parse(utf8.decode(data)).rootElement;
    final required = (root.getAttribute('requiredextensions') ?? '').split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    for (final prefix in required) {
      final declarations = root.attributes.where((a) => a.name.qualified == 'xmlns:$prefix');
      final uri = declarations.isEmpty ? '' : declarations.first.value;
      if (uri != 'http://schemas.microsoft.com/3dmanufacturing/production/2015/06' &&
          uri != 'http://schemas.microsoft.com/3dmanufacturing/material/2015/02') {
        throw const FormatException('3MF benötigt eine noch nicht unterstützte Erweiterung.');
      }
    }
    if (root.name.local != 'model') throw const FormatException('Ungültiges 3MF-Modell.');
    return root;
  });
  var mainPath = files.containsKey('3D/3dmodel.model') ? '3D/3dmodel.model' : '';
  final rels = files['_rels/.rels'];
  if (rels != null) {
    final data = rels.content;
    if (data is List<int>) {
      final doc = XmlDocument.parse(utf8.decode(data));
      for (final rel in doc.descendants.whereType<XmlElement>()) {
        if ((rel.getAttribute('Type') ?? '').endsWith('/3dmodel')) {
          if (rel.getAttribute('TargetMode') == 'External') throw const FormatException('Externes 3MF-Modell nicht unterstützt.');
          mainPath = _partPath('', rel.getAttribute('Target') ?? '');
          break;
        }
      }
    }
  }
  if (mainPath.isEmpty) throw const FormatException('3MF-Hauptmodell fehlt.');
  final main = model(mainPath);
  double unit(XmlElement root) => switch(root.getAttribute('unit') ?? 'millimeter') {
    'micron' => .001, 'millimeter' => 1, 'centimeter' => 10,
    'inch' => 25.4, 'foot' => 304.8, 'meter' => 1000,
    _ => throw const FormatException('Unbekannte 3MF-Einheit.'),
  };
  final scale = unit(main);
  final output = _TriangleBuffer();
  final active = <String>{};
  void emit(String path, int id, List<_Transform> transforms, int depth) {
    if (depth > 64) throw const FormatException('3MF-Komponenten sind zu tief verschachtelt.');
    final resourceKey = '$path#$id';
    if (!active.add(resourceKey)) throw const FormatException('Zyklische 3MF-Komponenten.');
    try {
      final root = model(path);
      if (unit(root) != scale) throw const FormatException('Unterschiedliche Einheiten in 3MF-Modellteilen noch nicht unterstützt.');
      final objects = objectMaps.putIfAbsent(path, () {
        final result = <int,XmlElement>{};
        for (final resources in _children(root,'resources')) {
          for (final object in _children(resources,'object')) {
            final key = int.parse(object.getAttribute('id') ?? '-1');
            if (key < 0 || result.containsKey(key)) throw const FormatException('Ungültige 3MF-Objektkennung.');
            result[key] = object;
          }
        }
        return result;
      });
      final object = objects[id];
      if (object == null) throw const FormatException('3MF-Objektreferenz fehlt.');
      final meshes = _children(object,'mesh').toList();
      if (meshes.isNotEmpty) {
        final mesh = meshes.single;
        final points = <List<double>>[];
        for (final group in _children(mesh,'vertices')) {
          for (final v in _children(group,'vertex')) {
            var point = [for (final axis in ['x','y','z']) double.parse(v.getAttribute(axis) ?? 'NaN')];
            for (final transform in transforms) { point = transform.apply(point); }
            point = point.map((v) => v*scale).toList();
            if (point.any((v) => !v.isFinite)) throw const FormatException('Ungültige 3MF-Koordinaten.');
            points.add(point);
          }
        }
        final reverse = transforms.fold<double>(1,(a,b) => a*b.determinant) < 0;
        for (final group in _children(mesh,'triangles')) {
          for (final triangle in _children(group,'triangle')) {
            final ids = [for (final key in ['v1','v2','v3']) int.parse(triangle.getAttribute(key) ?? '-1')];
            if (ids.any((i) => i < 0 || i >= points.length)) throw const FormatException('Ungültige 3MF-Dreiecksreferenz.');
            output.add(points[ids[0]],points[ids[reverse ? 2 : 1]],points[ids[reverse ? 1 : 2]]);
          }
        }
      } else {
        final groups = _children(object,'components').toList();
        if (groups.isEmpty) throw const FormatException('3MF-Objekt enthält kein unterstütztes Netz.');
        for (final component in _children(groups.single,'component')) {
          final paths = component.attributes.where((a) => a.name.local == 'path');
          final targetPath = paths.isEmpty ? path : _partPath(path,paths.first.value);
          emit(targetPath,int.parse(component.getAttribute('objectid') ?? '-1'),
            [_Transform.parse(component.getAttribute('transform')), ...transforms],depth+1);
        }
      }
    } finally { active.remove(resourceKey); }
  }
  final builds = _children(main,'build').toList();
  if (builds.isEmpty) throw const FormatException('3MF enthält keine Druckanordnung.');
  for (final item in _children(builds.single,'item')) {
    if (item.getAttribute('printable') == '0' || item.getAttribute('printable') == 'false') continue;
    final paths = item.attributes.where((a) => a.name.local == 'path');
    final itemPath = paths.isEmpty ? mainPath : _partPath(mainPath,paths.first.value);
    emit(itemPath,int.parse(item.getAttribute('objectid') ?? '-1'),
      [_Transform.parse(item.getAttribute('transform'))],0);
  }
  return output.finish();
}

Iterable<XmlElement> _children(XmlElement element, String name) => element.childElements.where((e) => e.name.local == name);
String _partPath(String from, String target) {
  final uri = Uri.parse(target.replaceAll('\\','/'));
  if (uri.hasScheme || uri.hasAuthority || uri.hasQuery || uri.hasFragment) throw const FormatException('Ungültiger 3MF-Modellpfad.');
  final parts = uri.path.startsWith('/') || from.isEmpty ? <String>[] : (from.split('/')..removeLast());
  for (final part in Uri.decodeComponent(uri.path).split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (parts.isEmpty) throw const FormatException('Ungültiger relativer 3MF-Pfad.');
      parts.removeLast();
    } else { parts.add(part); }
  }
  return parts.join('/');
}
class _Transform {
  _Transform(this.m);
  final List<double> m;
  factory _Transform.parse(String? value) {
    final m = value == null ? <double>[1,0,0,0,1,0,0,0,1,0,0,0]
      : value.trim().split(RegExp(r'\s+')).map(double.parse).toList();
    if (m.length != 12 || m.any((v) => !v.isFinite)) throw const FormatException('Ungültige 3MF-Transformation.');
    final transform = _Transform(m);
    if (transform.determinant.abs() < 1e-12) throw const FormatException('Singuläre 3MF-Transformation.');
    return transform;
  }
  double get determinant => m[0]*(m[4]*m[8]-m[5]*m[7])-m[1]*(m[3]*m[8]-m[5]*m[6])+m[2]*(m[3]*m[7]-m[4]*m[6]);
  List<double> apply(List<double> p) => [
    p[0]*m[0]+p[1]*m[3]+p[2]*m[6]+m[9],
    p[0]*m[1]+p[1]*m[4]+p[2]*m[7]+m[10],
    p[0]*m[2]+p[1]*m[5]+p[2]*m[8]+m[11],
  ];
}
class _TriangleBuffer {
  final chunks = <Float64List>[];
  Float64List current = Float64List(73728);
  int used = 0, count = 0;
  void add(List<double> a,List<double> b,List<double> c) {
    if (++count > 2500000) throw const FormatException('3MF enthält mehr als 2,5 Millionen Dreiecke.');
    for (final point in [a,b,c]) {
      for (final v in point) {
        if (used == current.length) { chunks.add(current); current = Float64List(73728); used = 0; }
        current[used++] = v;
      }
    }
  }
  Float64List finish() {
    if (count == 0) throw const FormatException('Keine druckbaren 3MF-Dreiecke.');
    final result = Float64List(count*9);
    var at = 0;
    for (final chunk in chunks) { result.setRange(at,at+chunk.length,chunk); at += chunk.length; }
    result.setRange(at,at+used,current);
    return result;
  }
}
