"""Bounded declarative CAD. Never execute model-generated Python or shell code."""
import ast
import math
import struct
import numpy as np
import manifold3d as m


def scalar(expression, answers):
    if not isinstance(expression, str) or len(expression) > 160:
        raise ValueError('Ungültiger Maßausdruck.')
    root = ast.parse(expression, mode='eval')
    if len(list(ast.walk(root))) > 64:
        raise ValueError('Maßausdruck ist zu komplex.')
    used = set()

    def evaluate(node, depth=0):
        if depth > 16:
            raise ValueError('Maßausdruck ist zu tief.')
        if isinstance(node, ast.Constant) and type(node.value) in (int, float):
            result = float(node.value)
        elif isinstance(node, ast.Name):
            result = answers.get(node.id)
            if type(result) not in (int, float):
                raise ValueError('Ein bestätigtes Zahlenmaß fehlt: ' + node.id)
            used.add(node.id)
        elif isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.UAdd, ast.USub)):
            result = evaluate(node.operand, depth+1) * (-1 if isinstance(node.op, ast.USub) else 1)
        elif isinstance(node, ast.BinOp) and isinstance(node.op, (ast.Add, ast.Sub, ast.Mult, ast.Div)):
            a, b = evaluate(node.left, depth+1), evaluate(node.right, depth+1)
            if isinstance(node.op, ast.Add): result = a+b
            elif isinstance(node.op, ast.Sub): result = a-b
            elif isinstance(node.op, ast.Mult): result = a*b
            elif b != 0: result = a/b
            else: raise ValueError('Division durch null in den Maßen.')
        else:
            raise ValueError('Nur Zahlenmaße und einfache Maßrechnungen sind erlaubt.')
        if not math.isfinite(result) or abs(result) > 10000:
            raise ValueError('Maß außerhalb des erlaubten Bereichs.')
        return result
    return evaluate(root.body), used


def build_stl(plan, answers, assumptions_accepted=False):
    if plan.get('status') != 'ready' or plan.get('blockers'):
        raise ValueError('Erst fehlende Angaben oder Widersprüche klären.')
    dimensions = plan.get('dimensions', [])
    if not dimensions or len(dimensions) > 32:
        raise ValueError('Keine gültigen Referenzmaße vorhanden.')
    numeric = {}
    for d in dimensions:
        key = d['id']
        value = answers.get(key)
        if d['kind'] == 'mm':
            if type(value) not in (int, float) or not math.isfinite(value) or not 0 < value <= 10000:
                raise ValueError('Bitte das Maß bestätigen: '+d['label'])
            numeric[key] = value
        elif not isinstance(value, str) or not value.strip() or len(value) > 500:
            raise ValueError('Bitte die Rückfrage beantworten: '+d['label'])
        elif d['choices'] and value not in d['choices']:
            raise ValueError('Ungültige Auswahl: '+d['label'])
    if not numeric:
        raise ValueError('Mindestens ein gemessenes Referenzmaß ist erforderlich.')
    if plan.get('assumptions') and not assumptions_accepted:
        raise ValueError('Die angezeigten Näherungen müssen bestätigt werden.')
    operations = plan.get('operations', [])
    if not 1 <= len(operations) <= 96:
        raise ValueError('Zu komplex für diese Rekonstruktion.')
    result = None
    used = set()
    for operation in operations:
        size, position = [], []
        for source, target in [(operation['size'], size), (operation['position'], position)]:
            if not isinstance(source, list) or len(source) != 3:
                raise ValueError('Drei Koordinaten erforderlich.')
            for expr in source:
                value, refs = scalar(expr, numeric)
                target.append(value); used.update(refs)
        rotation = operation['rotation']
        if len(rotation) != 3 or any(type(v) not in (int,float) or not math.isfinite(v) or abs(v)>360 for v in rotation):
            raise ValueError('Ungültige Drehung.')
        if any(v<0 or v>2000 for v in size):
            raise ValueError('Ungültige Bauteilgröße.')
        kind = operation['kind']
        if kind == 'box' and min(size) >= .1:
            solid = m.Manifold.cube(size, center=True)
        elif kind == 'cylinder' and size[2] >= .1 and max(size[:2]) >= .1:
            solid = m.Manifold.cylinder(size[2],size[0]/2,size[1]/2,64,center=True)
        elif kind == 'sphere' and size[0] >= .1 and size[0] == size[1] == size[2]:
            solid = m.Manifold.sphere(size[0]/2,48)
        else:
            raise ValueError('Nicht unterstützte oder leere Grundform.')
        solid = solid.rotate(rotation).translate(position)
        if operation['op'] == 'add': result = solid if result is None else result+solid
        elif operation['op'] == 'subtract' and result is not None: result = result-solid
        else: raise ValueError('Das Modell muss mit einer festen Grundform beginnen.')
        if result.num_tri() > 500000:
            raise ValueError('Das Modell enthält zu viele Dreiecke.')
    if set(numeric)-used:
        raise ValueError('Bestätigte Maße sind noch nicht mit der Geometrie verknüpft: '+', '.join(sorted(set(numeric)-used)))
    if result is None or result.is_empty() or result.status() != m.Error.NoError or result.volume() <= 0:
        raise ValueError('Kein geschlossenes, druckbares Volumen entstanden.')
    mesh = result.to_mesh()
    points = np.asarray(mesh.vert_properties)[:,:3]
    if not np.isfinite(points).all() or np.ptp(points,axis=0).max() > 2000:
        raise ValueError('Ungültige Modellausdehnung.')
    triangles = points[np.asarray(mesh.tri_verts)]
    # Manifold produces closed oriented triangles; retain normals and real mm.
    data = bytearray(b'PhotoPart parametric reconstruction; units mm'.ljust(80,b'\0'))
    data.extend(struct.pack('<I',len(triangles)))
    for triangle in triangles:
        normal = np.cross(triangle[1]-triangle[0],triangle[2]-triangle[0])
        length = np.linalg.norm(normal)
        if length <= 0: raise ValueError('Entartete Dreiecke im Modell.')
        data.extend(struct.pack('<12fH',*(normal/length),*triangle.reshape(-1),0))
    return bytes(data)
