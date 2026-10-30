import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'plate_geometry.dart';
import 'studio_project.dart';
import 'project_optimizer.dart';
import 'gcode_preview.dart';

const slicerChannel=MethodChannel('print_optimizer/slicer');
bool supportsLocalSlicer(StudioProject project){
  final name=project.printer.trim().toLowerCase();
  final nozzle=double.tryParse(project.nozzle.replaceAll(',','.'));
  return ['anycubic kobra s1','kobra s1'].contains(name)&&nozzle!=null&&(nozzle-.4).abs()<1e-6&&project.bed.valid&&
    project.bed.width<=250&&project.bed.depth<=250&&project.bed.height<=250;
}
Map<String,dynamic> localSlicerSettings((StudioProject,String) input){
  final p=input.$1;
  if(!supportsLocalSlicer(p))throw const FormatException('Der lokale Slicer unterstützt zunächst Kobra S1 mit 0,4-mm-Düse und maximal 250 mm Bauraum.');
  if(p.parts.isEmpty||p.parts.any((part)=>!part.fits(p.bed.width,p.bed.depth,p.bed.height)))throw const FormatException('Alle Teile müssen in den Bauraum passen.');
  for(var i=0;i<p.parts.length;i++)for(var j=i+1;j<p.parts.length;j++){
    if(p.parts[i].bounds.overlaps(p.parts[j].bounds))throw const FormatException('Platzbereiche überlappen. Teile vor dem Slicen weiter auseinanderschieben.');
  }
  final recipe=p.recipe;
  if(recipe==null)throw const FormatException('Bitte zuerst die Fragen unter Einstellungen beantworten.');
  if(double.tryParse(recipe.nozzle.replaceAll(',','.'))!=double.tryParse(p.nozzle.replaceAll(',','.')))throw const FormatException('Düse in den Projekteinstellungen erneut wählen.');
  final advice=recipe.advice,temperature=materialTemperatures(advice.material)!;
  final geometry=projectNozzleGeometry(recipe),speeds=printSpeeds(recipe);
  final flowSpeed=speeds.flowLimit/(geometry.line*geometry.layer);
  double speed(num value)=>math.min(value.toDouble(),math.min(150,flowSpeed));
  final fan=advice.material=='PLA'?100:advice.material=='ASA'?0:50;
  final overrides=<String,Object>{
    'machine_width':p.bed.width,'machine_depth':p.bed.depth,'machine_height':p.bed.height,
    'machine_center_is_zero':false,'center_object':false,'machine_extruder_count':1,'extruder_nr':0,
    'machine_nozzle_size':.4,'material_diameter':1.75,'machine_gcode_flavor':'RepRap (Marlin/Sprinter)',
    'machine_heated_bed':true,'machine_heated_build_volume':false,'machine_extruder_cooling_fan_number':1,
    // Official Kobra S1 startup macro; the firmware performs its normal startup.
    // Source: ANYCUBIC-3D/AnycubicSlicerNext, machine S1 0.4 nozzle profile.
    'machine_start_gcode':'G9111 bedTemp=${temperature.bed} extruderTemp=${temperature.nozzle}\nM117\nG90\nM82\nG92 E0',
    'machine_end_gcode':'M400\nG92 E0\nG1 E-0.8 F1500\nM104 S0\nM140 S0\nM106 P1 S0\nM106 P2 S0\nM106 P3 S0\nM84',
    'machine_max_feedrate_x':150,'machine_max_feedrate_y':150,'machine_max_feedrate_z':10,'machine_max_feedrate_e':30,
    'machine_max_acceleration_x':1000,'machine_max_acceleration_y':1000,'machine_max_acceleration_z':100,'machine_max_acceleration_e':1000,
    'machine_acceleration':1000,'acceleration_enabled':false,'jerk_enabled':false,
    'material_print_temperature':temperature.nozzle,'material_print_temperature_layer_0':temperature.nozzle,
    'material_initial_print_temperature':temperature.nozzle,'material_final_print_temperature':temperature.nozzle,
    'material_standby_temperature':temperature.nozzle,'material_bed_temperature':temperature.bed,'material_bed_temperature_layer_0':temperature.bed,
    'material_flow':100,'material_flow_layer_0':100,'relative_extrusion':false,
    'layer_height':geometry.layer,'layer_height_0':geometry.first,'line_width':geometry.line,'initial_layer_line_width_factor':100,
    'wall_line_count':advice.walls,'wall_thickness':advice.walls*geometry.line,'top_layers':geometry.top,'bottom_layers':geometry.bottom,
    'top_thickness':geometry.top*geometry.layer,'bottom_thickness':geometry.bottom*geometry.layer,'infill_sparse_thickness':geometry.layer,
    'infill_pattern':'gyroid','infill_sparse_density':advice.infill,'infill_line_distance':geometry.line*100/advice.infill,
    'speed_print':speed(speeds.inner),'speed_wall':speed(speeds.outer),'speed_wall_0':speed(speeds.outer),'speed_wall_x':speed(speeds.inner),
    'speed_infill':speed(speeds.infill),'speed_topbottom':speed(speeds.top),'speed_roofing':speed(speeds.top),
    'speed_layer_0':speeds.first,'speed_print_layer_0':speeds.first,'speed_travel_layer_0':80,'speed_travel':120,
    'bridge_settings_enabled':true,'bridge_skin_speed':speed(speeds.bridge),'bridge_wall_speed':speed(speeds.bridge),
    'retraction_enable':true,'retraction_amount':advice.material == 'TPU' ? 0.4 : 0.8,'retraction_speed':25,'retraction_retract_speed':25,'retraction_prime_speed':25,
    'retraction_hop_enabled':false,'retraction_extra_prime_amount':0,
    'cool_fan_enabled':fan>0,'cool_fan_speed':fan,'cool_fan_speed_min':fan,'cool_fan_speed_max':fan,'cool_fan_speed_0':0,'cool_fan_full_layer':3,
    'support_enable':true,'support_structure':'normal','support_type':'everywhere','support_angle':50,'support_pattern':'zigzag',
    'support_line_distance':geometry.line*100/15,'support_xy_distance':.6,'support_z_distance':geometry.layer*2,
    'support_top_distance':geometry.layer*2,'support_bottom_distance':geometry.layer*2,
    'adhesion_type':advice.material=='ASA'?'brim':'none','brim_width':8,'brim_line_count':(8/geometry.line).ceil(),'brim_outside_only':true,
  };
  final definition=jsonDecode(input.$2) as Map<String,dynamic>;
  final settings=Map<String,dynamic>.from(definition['settings'] as Map);
  for(final key in settings.keys.where((key)=>key.endsWith('line_width'))){overrides[key]=geometry.line;}
  for(final entry in overrides.entries){settings[entry.key]={'default_value':entry.value};}
  definition['settings']=settings;
  return definition;
}
class LocalSliceResult {
  const LocalSliceResult(this.path,this.directory,this.preview);
  final String path;final Directory directory;final GcodePreview preview;
}
class LocalSlicer {
  bool _cancelled=false;
  Future<void> cancel()async{_cancelled=true;if(Platform.isAndroid)await slicerChannel.invokeMethod<void>('cancel');}
  void checkCancelled(){if(_cancelled)throw const FormatException('Berechnung abgebrochen.');}
  Future<LocalSliceResult> run(StudioProject project)async{
    _cancelled=false;
    if(!Platform.isAndroid)throw const FormatException('Der integrierte Slicer ist derzeit für Android verfügbar.');
    final defaults=await rootBundle.loadString('assets/slicer/defaults.json');
    final definition=await compute(localSlicerSettings,(project,defaults));checkCancelled();
    final directory=await Directory('${(await getTemporaryDirectory()).path}/slicer').create(recursive:true);
    final job=await directory.createTemp('job-');
    try{
      final model=File('${job.path}/plate.stl'),settings=File('${job.path}/settings.json'),output=File('${job.path}/plate.gcode');
      final bytes=await compute(encodePlateStl,project.parts);checkCancelled();
      await model.writeAsBytes(bytes,flush:true);await settings.writeAsString(jsonEncode(definition),flush:true);checkCancelled();
      final path=await slicerChannel.invokeMethod<String>('slice',{'model':model.path,'settings':settings.path,'output':output.path});
      if(path==null||await File(path).resolveSymbolicLinks()!=await output.resolveSymbolicLinks())throw const FormatException('Slicer lieferte keine gültige Ausgabedatei.');
      final preview=await compute(parseGcodeFile,(output.path,project.bed));
      checkCancelled();
      if(preview.outsideBed)throw const FormatException('Erzeugte Druckbahnen überschreiten den Bauraum. Teile weiter vom Rand platzieren; bei ASA auch den 8-mm-Brim berücksichtigen.');
      await model.delete();await settings.delete();
      return LocalSliceResult(output.path,job,preview);
    }catch(_){if(await job.exists())await job.delete(recursive:true);rethrow;}
  }
}
