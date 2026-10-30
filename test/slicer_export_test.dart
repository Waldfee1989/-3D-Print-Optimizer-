import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:print_optimizer/project_optimizer.dart';
import 'package:print_optimizer/slicer_export.dart';

PrintProject project({bool functional = false,bool warm = false,bool flexible = false,String nozzle = '0.4',String support = 'Stützen empfohlen'}) =>
  PrintProject(id: '20261030',fileName: 'Teil.stl',dimensions: '20 mm',printer: 'Anycubic Kobra S1',
    slicer: 'Anycubic Slicer Next',nozzle: nozzle,functional: functional,warm: warm,flexible: flexible,
    supportStatus: support);

void main() {
  test('ZIP contains only two importable presets with valid metadata and correct material inheritance', () {
    for (final p in [project(),project(functional: true),project(warm: true),project(flexible: true)]) {
      final files = ZipDecoder().decodeBytes(createSlicerPresetZip(p));
      expect(files.files.length,2);
      for (final file in files.files) {
        expect(file.name,endsWith('.json'));
        final map = jsonDecode(utf8.decode(file.content as List<int>)) as Map<String,dynamic>;
        expect(map['version'],matches(RegExp(r'^\d+\.\d+\.\d+$')));
        expect(map['from'],'User');
        expect(map['compatible_printers'],['Anycubic Kobra S1 0.4 nozzle']);
        expect(map.containsKey('printer_settings_id'),isFalse);
        if (map['type'] == 'process') {
          expect(map['print_settings_id'],map['name']);
          expect(map['wall_loops'],'${p.advice.walls}');
          expect(map['sparse_infill_density'],'${p.advice.infill}%');
          expect(map['outer_wall_speed'],'${printSpeeds(p).outer}');
          expect(map['support_threshold_angle'],'40');
          expect(map['enable_support'],'1');
        } else {
          expect(map['filament_settings_id'],[map['name']]);
          expect(map['inherits'],'Anycubic ${p.advice.material} @Anycubic Kobra S1 0.4 nozzle');
          expect(map['nozzle_temperature'],['${materialTemperatures(p.advice.material)!.nozzle}']);
          expect(map['textured_plate_temp'],['${materialTemperatures(p.advice.material)!.bed}']);
          expect(map['cool_plate_temp'],map['textured_plate_temp']);
        }
      }
    }
  });
  test('Unknown support status remains enabled; known support-free hint may disable it', () {
    expect(createSlicerPresetFiles(project(support: 'Im Slicer prüfen'))['Druckprofil.json']!['enable_support'],'1');
    expect(createSlicerPresetFiles(project(support: 'Voraussichtlich keine Stützen nötig'))['Druckprofil.json']!['enable_support'],'0');
    expect(supportsSlicerPresetExport(project(nozzle: '0.6')),isFalse);
    expect(() => createSlicerPresetZip(project(nozzle: '0.6')),throwsFormatException);
  });
  test('Geometry changes survive persistence and remain explicit in the settings', () {
    final p = PrintProject(id: 'x',fileName: 'x.stl',dimensions: '40 mm',printer: 'Anycubic Kobra S1',
      slicer: 'Anycubic Slicer Next',nozzle: '.4',modelScale: 2,orientation: 'Optimiert · angepasste STL verwenden');
    final restored = PrintProject.fromJson(jsonDecode(jsonEncode(p.toJson())) as Map<String,dynamic>);
    expect(restored.modelScale,2);
    expect(projectSettings(restored)['Modelldatei'],'Angepasste STL verwenden');
    expect(restored.orientation,p.orientation);
  });
}
