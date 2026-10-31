import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:print_optimizer/local_slicer.dart';
import 'package:print_optimizer/plate_geometry.dart';
import 'package:print_optimizer/printer_setup.dart';
import 'package:print_optimizer/project_optimizer.dart';
import 'package:print_optimizer/studio_project.dart';
import 'geometry_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  StudioProject project(PrinterBed bed, List<(double, double)> centers) {
    final part = PlatePart(name: 'Testwuerfel.stl', vertices: denseCube(1), unitScale: 10,
      width: 20, depth: 20, height: 20);
    return StudioProject(id: 'positions', name: 'Positionspruefung', printer: 'Anycubic Kobra S1',
      slicer: 'Anycubic Slicer Next', nozzle: '0.4', bed: bed,
      parts: [for (var i = 0; i < centers.length; i++) PlatePlacement(id: '$i', part: part, x: centers[i].$1, y: centers[i].$2)],
      recipe: PrintProject(id: 'positions', fileName: 'Positionspruefung', dimensions: '20 mm',
        printer: 'Anycubic Kobra S1', slicer: 'Anycubic Slicer Next', nozzle: '0.4'));
  }
  test('Exported bed positions survive the real slicer import; outside parts stay blocked', () async {
    final defaults = await rootBundle.loadString('assets/slicer/defaults.json');
    final cases = {
      'front': project(const PrinterBed(250, 250, 250), [(25, 30)]),
      'center': project(const PrinterBed(250, 250, 250), [(125, 125)]),
      'back': project(const PrinterBed(250, 250, 250), [(225, 225)]),
      'two_parts': project(const PrinterBed(250, 250, 250), [(35, 40), (205, 210)]),
      'rectangular': project(const PrinterBed(200, 180, 250), [(120, 100)]),
    };
    final fixtureRoot = Platform.environment['SLICER_FIXTURE_DIR'];
    for (final entry in cases.entries) {
      final p = entry.value, settings = localSlicerSettings((entry.value, defaults));
      final values = settings['settings'] as Map;
      expect(values['machine_center_is_zero']['default_value'], false);
      expect(values['center_object']['default_value'], false);
      expect(values['mesh_position_x']['default_value'], -p.bed.width / 2);
      expect(values['mesh_position_y']['default_value'], -p.bed.depth / 2);
      if (fixtureRoot != null) {
        final dir = Directory('$fixtureRoot/${entry.key}')..createSync(recursive: true);
        File('${dir.path}/plate.stl').writeAsBytesSync(encodePlateStl(p.parts));
        File('${dir.path}/settings.json').writeAsStringSync(jsonEncode(settings));
        File('${dir.path}/expected.json').writeAsStringSync(jsonEncode({
          'bed': [p.bed.width, p.bed.depth, p.bed.height],
          'parts': [for (final part in p.parts) [part.bounds.left, part.bounds.top, part.bounds.right, part.bounds.bottom, part.part.height]],
        }));
      }
    }
    final invalid = project(const PrinterBed(250, 250, 250), [(245, 125)]);
    expect(() => localSlicerSettings((invalid, defaults)), throwsFormatException);
  });
}
