"""Run the real engine on a closed 20 mm cube and inspect its G-code."""
import json
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile

with tempfile.TemporaryDirectory() as temp:
    root=Path(temp);model=root/'cube.stl';output=root/'cube.gcode'
    vertices=[(100,100,0),(120,100,0),(120,120,0),(100,120,0),(100,100,20),(120,100,20),(120,120,20),(100,120,20)]
    faces=[(0,2,1),(0,3,2),(4,5,6),(4,6,7),(0,1,5),(0,5,4),(3,7,6),(3,6,2),(0,4,7),(0,7,3),(1,2,6),(1,6,5)]
    with model.open('wb') as stream:
        stream.write(bytes(80));stream.write(struct.pack('<I',12))
        for face in faces:stream.write(struct.pack('<12fH',0,0,0,*(n for i in face for n in vertices[i]),0))
    definition=json.loads(Path('assets/slicer/defaults.json').read_text())
    settings={
      'machine_width':250,'machine_depth':250,'machine_height':250,'machine_extruder_count':1,'material_diameter':1.75,'machine_nozzle_size':.4,
      'machine_start_gcode':'G90\nM82\nM140 S55\nM104 S205\nG28\nM190 S55\nM109 S205\nG92 E0',
      'machine_end_gcode':'M400\nM104 S0\nM140 S0\nM107',
      'layer_height':.2,'layer_height_0':.2,'line_width':.42,'wall_line_width':.42,'wall_line_width_0':.42,'wall_line_width_x':.42,
      'wall_line_count':3,'top_layers':5,'bottom_layers':5,'infill_line_distance':2.1,'infill_pattern':'gyroid','adhesion_type':'none',
      'support_enable':False,'material_print_temperature':205,'material_print_temperature_layer_0':205,'material_bed_temperature':55,
      'material_bed_temperature_layer_0':55,'speed_print':50,'speed_wall':35,'speed_wall_0':35,'speed_wall_x':45,'speed_infill':50,
      'speed_layer_0':20,'speed_topbottom':30,'speed_travel':100,'speed_travel_layer_0':80,
      'retraction_amount':.8,'retraction_speed':25,'retraction_retract_speed':25,'retraction_prime_speed':25,
      'machine_max_acceleration_x':1000,'machine_max_acceleration_y':1000,'machine_max_acceleration_z':100,'machine_max_acceleration_e':1000,
      'machine_max_feedrate_x':150,'machine_max_feedrate_y':150,'machine_max_feedrate_z':10,'machine_max_feedrate_e':30,
      'machine_acceleration':1000,'acceleration_enabled':False,'jerk_enabled':False,'center_object':False,
    }
    for key,value in settings.items():definition['settings'][key]={'default_value':value}
    config=root/'printer.json';config.write_text(json.dumps(definition))
    result=subprocess.run([str(Path(sys.argv[1]).resolve()),'slice','-j',str(config),'-o',str(output),'-l',str(model)],capture_output=True,text=True,timeout=180)
    if result.returncode:raise RuntimeError(result.stderr[-12000:])
    text=output.read_text();layers=[int(n) for n in re.findall(r'^;LAYER:(\d+)',text,re.M)]
    if len(layers)<95 or len(layers)>105:raise AssertionError(f'Unexpected layers: {len(layers)}')
    if 'M104 S205' not in text or 'M140 S55' not in text or 'M104 S0' not in text:raise AssertionError('Temperatures missing')
    position={'X':0.,'Y':0.,'Z':0.,'E':0.};extruding=0
    for line in text.splitlines():
        command=line.split(';',1)[0].strip()
        if not re.match(r'G(?:0|1|92)(?:\s|$)',command):continue
        values={k:float(v) for k,v in re.findall(r'([XYZE])\s*(-?\d*\.?\d+)',command)}
        if command.startswith('G92'):position.update(values);continue
        if values.get('E',position['E'])>position['E']+1e-6 and ('X' in values or 'Y' in values):
            extruding+=1
            for key,maximum in [('X',250),('Y',250),('Z',250)]:
                value=values.get(key,position[key])
                if not 0<=value<=maximum:raise AssertionError(f'Out-of-bed path: {command}')
        position.update(values)
    if extruding<300:raise AssertionError(f'No actual toolpaths: {extruding}')
    print(f'REAL_ENGINE_OK: {len(layers)} layers, {extruding} extrusion moves, {len(text)} G-code bytes')
