"""Verify real toolpaths from production Dart export/settings at several positions."""
import json
from pathlib import Path
import re
import subprocess
import sys

engine = str(Path(sys.argv[1]).resolve())
root = Path(sys.argv[2])
fixtures = sorted(root.glob('*/expected.json'))
if len(fixtures) < 5:
    raise AssertionError('The production export/settings fixtures are missing')
for manifest in fixtures:
    folder = manifest.parent
    expected = json.loads(manifest.read_text())
    output = folder / 'plate.gcode'
    result = subprocess.run([engine, 'slice', '-j', str(folder / 'settings.json'),
                             '-l', str(folder / 'plate.stl'), '-o', str(output)],
                            capture_output=True, text=True, timeout=180)
    if result.returncode:
        raise RuntimeError(result.stderr[-2000:])
    position = dict.fromkeys('XYZE', 0.)
    lows = dict.fromkeys('XY', float('inf'))
    highs = dict.fromkeys('XY', float('-inf'))
    moves = 0
    for line in output.read_text().splitlines():
        cmd = line.split(';', 1)[0].strip()
        if not re.match(r'G(?:0|1|92)(?:\s|$)', cmd):
            continue
        values = {k: float(v) for k, v in re.findall(r'([XYZE])\s*([-+]?\d*\.?\d+)', cmd)}
        if cmd.startswith('G92'):
            position.update(values)
            continue
        target = {**position, **values}
        for axis, maximum in zip('XYZ', expected['bed']):
            if not -.05 <= target[axis] <= maximum + .05:
                raise AssertionError(f'{folder.name}: out-of-bed motion {cmd}')
        if target['E'] > position['E'] + 1e-6 and any(k in values for k in 'XY'):
            moves += 1
            for point in (position, target):
                for axis in 'XY':
                    lows[axis] = min(lows[axis], point[axis])
                    highs[axis] = max(highs[axis], point[axis])
                if not any(p[0] - .5 <= point['X'] <= p[2] + .5 and
                           p[1] - .5 <= point['Y'] <= p[3] + .5 for p in expected['parts']):
                    raise AssertionError(f'{folder.name}: extrusion no longer follows the placed parts: {point}')
        position.update(values)
    if moves < 100:
        raise AssertionError(f'{folder.name}: no real extrusion paths')
    wanted = [min(p[0] for p in expected['parts']), min(p[1] for p in expected['parts']),
              max(p[2] for p in expected['parts']), max(p[3] for p in expected['parts'])]
    measured = [lows['X'], lows['Y'], highs['X'], highs['Y']]
    if any(abs(a - b) > .5 for a, b in zip(wanted, measured)):
        raise AssertionError(f'{folder.name}: position/size changed: {measured}, expected {wanted}')
    print(f'PLACEMENT_OK {folder.name}: {moves} extrusion moves, XY={measured}')
