import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:print_optimizer/model_3mf.dart';
import 'package:print_optimizer/support_analysis.dart';

const tetra = '<mesh><vertices>'
  '<vertex x="0" y="0" z="0"/><vertex x="2" y="0" z="0"/>'
  '<vertex x="0" y="2" z="0"/><vertex x="0" y="0" z="2"/>'
  '</vertices><triangles><triangle v1="0" v2="2" v3="1"/>'
  '<triangle v1="0" v2="1" v3="3"/><triangle v1="0" v2="3" v3="2"/>'
  '<triangle v1="1" v2="2" v3="3"/></triangles></mesh>';
String model(String objects, String build, {String unit = 'millimeter', String extra = ''}) =>
  '<model xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02" '
  'xmlns:p="http://schemas.microsoft.com/3dmanufacturing/production/2015/06" unit="$unit" $extra>'
  '<resources>$objects</resources><build>$build</build></model>';
Uint8List package(Map<String,String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}
void main() {
  test('Build transforms and units apply; unreferenced resources stay excluded', () {
    final bytes = package({'3D/3dmodel.model': model('<object id="1">$tetra</object><object id="2">$tetra</object>',
      '<item objectid="1" transform="1 0 0 0 0 1 0 -1 0 10 20 30"/>', unit: 'inch')});
    final v = readThreeMfTriangles(bytes);
    expect(v.length, 36);
    expect(v.take(3).toList(), orderedEquals([254.0,508.0,762.0]));
    expect(v.every((x) => x.isFinite), isTrue);
  });
  test('Nested production part and build transforms compose in the right order', () {
    final bytes = package({
      '3D/3dmodel.model': model('<object id="9"><components><component objectid="1" p:path="/3D/Objects/part.model" '
        'transform="1 0 0 0 1 0 0 0 1 5 0 0"/></components></object>',
        '<item objectid="9" transform="1 0 0 0 1 0 0 0 1 0 6 0"/>'),
      '3D/Objects/part.model': model('<object id="1">$tetra</object>',''),
    });
    final v = readThreeMfTriangles(bytes);
    expect(v.length, 36);
    expect(v.take(3).toList(), orderedEquals([5.0,6.0,0.0]));
    expect(assessSupports(Float32List.fromList(v)).status, 'Voraussichtlich keine Stützen nötig');
  });
  test('Mirrored transforms preserve outward winding and permit support analysis', () {
    final bytes = package({'3D/3dmodel.model': model('<object id="1">$tetra</object>',
      '<item objectid="1" transform="-1 0 0 0 1 0 0 0 1 0 0 0"/>')});
    final v = readThreeMfTriangles(bytes);
    expect(assessSupports(Float32List.fromList(v)).status, 'Voraussichtlich keine Stützen nötig');
  });
  test('Missing, cyclic, singular and unsupported required geometry fail explicitly', () {
    for (final xml in [
      model('<object id="1">$tetra</object>','<item objectid="99"/>'),
      model('<object id="1"><components><component objectid="1"/></components></object>','<item objectid="1"/>'),
      model('<object id="1">$tetra</object>','<item objectid="1" transform="0 0 0 0 0 0 0 0 0 0 0 0"/>'),
      model('<object id="1">$tetra</object>','<item objectid="1"/>',extra: 'xmlns:s="urn:unsupported-slice" requiredextensions="s"'),
    ]) {
      expect(() => readThreeMfTriangles(package({'3D/3dmodel.model': xml})), throwsFormatException);
    }
  });
  test('Package relationships select main part and relative paths stay inside package', () {
    final bytes = package({
      '_rels/.rels': '<Relationships><Relationship Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel" Target="/Models/main.model"/></Relationships>',
      'Models/main.model': model('<object id="8"><components><component objectid="1" p:path="../Parts/mesh.model"/></components></object>','<item objectid="8"/>'),
      'Parts/mesh.model': model('<object id="1">$tetra</object>',''),
    });
    expect(readThreeMfTriangles(bytes).length, 36);
    final bad = package({'3D/3dmodel.model': model('<object id="1"><components><component objectid="2" p:path="../../../outside.model"/></components></object>','<item objectid="1"/>')});
    expect(() => readThreeMfTriangles(bad), throwsFormatException);
  });
}
