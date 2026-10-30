import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'project_optimizer.dart';

// Import contract and setting names checked against AnycubicSlicerNext:
// src/libslic3r/PresetBundle.cpp (import_json_presets), PrintConfig.cpp,
// resources/profiles/Anycubic/{process,filament} for Kobra S1 0.4.
// https://github.com/ANYCUBIC-3D/AnycubicSlicerNext
bool supportsSlicerPresetExport(PrintProject p) =>
  p.slicer == 'Anycubic Slicer Next' && p.printer.trim().toLowerCase() == 'anycubic kobra s1' &&
  double.tryParse(p.nozzle.replaceAll(',','.')) == .4;

Map<String, Map<String,dynamic>> createSlicerPresetFiles(PrintProject p) {
  if (!supportsSlicerPresetExport(p)) throw const FormatException('Profilimport ist für Anycubic Slicer Next / Kobra S1 / 0,4 mm eingerichtet.');
  final a = p.advice, t = materialTemperatures(p.advice.material);
  if (t == null) throw const FormatException('Unbekanntes Material.');
  final speeds = printSpeeds(p);
  final id = p.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'),'_');
  final short = id.length > 48 ? id.substring(0,48) : id;
  final processName = 'Print Optimizer Druck $short';
  final filamentName = 'Print Optimizer ${a.material} $short';
  const printer = 'Anycubic Kobra S1 0.4 nozzle';
  final geometry = projectNozzleGeometry(p);
  final layer = geometry.layer;
  final supports = !p.supportStatus.startsWith('Voraussichtlich keine');
  final process = <String,dynamic>{
    'type': 'process','name': processName,'from': 'User','version': '1.0.0','instantiation': 'true',
    'inherits': '0.20mm Standard @Anycubic Kobra S1 0.4 nozzle',
    'print_settings_id': processName,'compatible_printers': [printer],
    'layer_height': '$layer','initial_layer_print_height': '${geometry.first}',
    'line_width': '${geometry.line}',
    'initial_layer_speed': '${speeds.first}','initial_layer_infill_speed': '${speeds.first}',
    'wall_loops': '${a.walls}','sparse_infill_density': '${a.infill}%',
    'sparse_infill_pattern': 'gyroid','top_shell_layers': '${geometry.top}',
    'bottom_shell_layers': '${geometry.bottom}',
    'top_shell_thickness': '0','bottom_shell_thickness': '0',
    'outer_wall_speed': '${speeds.outer}','inner_wall_speed': '${speeds.inner}',
    'sparse_infill_speed': '${speeds.infill}','internal_solid_infill_speed': '${speeds.infill}',
    'top_surface_speed': '${speeds.top}','gap_infill_speed': '${speeds.top}',
    'bridge_speed': '${speeds.bridge}','internal_bridge_speed': '100%',
    'enable_support': supports ? '1' : '0','support_type': 'tree(auto)',
    'support_on_build_plate_only': '0',
    // Slicer angle is measured from the plate: 90 - app's 50 from vertical.
    'support_threshold_angle': '40',
    'brim_width': a.material == 'ASA' ? '8' : '5','brim_type': 'auto_brim',
  };
  final filament = <String,dynamic>{
    'type': 'filament','name': filamentName,'from': 'User','version': '1.0.0','instantiation': 'true',
    'inherits': 'Anycubic ${a.material} @Anycubic Kobra S1 0.4 nozzle',
    'filament_settings_id': [filamentName],'compatible_printers': [printer],
    'filament_type': [a.material], 'nozzle_temperature': ['${t.nozzle}'],
    'nozzle_temperature_initial_layer': ['${t.nozzle}'],
    'hot_plate_temp': ['${t.bed}'],'hot_plate_temp_initial_layer': ['${t.bed}'],
    'textured_plate_temp': ['${t.bed}'],'textured_plate_temp_initial_layer': ['${t.bed}'],
    // S1's stock preset also exposes Cool Plate; keep the chosen bed temperature
    // consistent when that plate type is currently selected.
    'cool_plate_temp': ['${t.bed}'],'cool_plate_temp_initial_layer': ['${t.bed}'],
    'filament_max_volumetric_speed': ['${speeds.flowLimit}'],
    'close_fan_the_first_x_layers': ['2'],'full_fan_speed_layer': ['3'],
    'filament_notes': ['Allgemeine Startwerte. Rollenetikett und Kalibrierung beachten. Prozess- und Filamentprofil gemeinsam auswählen.'],
  };
  if (a.material != 'TPU') {
    final fan = a.material == 'PLA' ? '100' : a.material == 'PETG' ? '50' : '0';
    filament['fan_min_speed'] = [fan]; filament['fan_max_speed'] = [fan];
  }
  return {'Druckprofil.json': process,'Filamentprofil.json': filament};
}

Uint8List createSlicerPresetZip(PrintProject p) {
  final archive = Archive();
  for (final file in createSlicerPresetFiles(p).entries) {
    final bytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(file.value));
    archive.addFile(ArchiveFile(file.key,bytes.length,bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}
