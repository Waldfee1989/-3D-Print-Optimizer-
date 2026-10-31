import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_design.dart';
import 'component_geometry.dart';
import 'component_preview.dart';
import 'plate_geometry.dart';

class ComponentBuilderPage extends StatefulWidget {
  const ComponentBuilderPage({
    super.key,
    required this.shape,
    required this.chooser,
  });
  final ComponentShape shape;
  final Widget chooser;
  @override
  State<ComponentBuilderPage> createState() => _ComponentBuilderPageState();
}

class _ComponentBuilderPageState extends State<ComponentBuilderPage> {
  final dimensions = List.generate(3, (_) => TextEditingController());
  final points = <Offset>[];
  PlatePart? created;
  String? error;
  bool busy = false;
  int revision = 0;
  bool get free => widget.shape == ComponentShape.contour;
  void invalidate() {
    revision++;
    created = null;
    error = null;
  }

  double? parse(String text) {
    final match = RegExp(
      r'^(\d+(?:[.,]\d+)?)\s*(mm|cm)?$',
      caseSensitive: false,
    ).firstMatch(text.trim());
    return match == null
        ? null
        : double.parse(match[1]!.replaceAll(',', '.')) *
              (match[2]?.toLowerCase() == 'cm' ? 10 : 1);
  }

  Future<void> create() async {
    final values = dimensions.map((c) => parse(c.text)).toList();
    if (values.any((v) => v == null)) {
      setState(
        () => error =
            'Bitte Breite, Länge und Höhe angeben. Auch cm sind möglich.',
      );
      return;
    }
    final spec = ComponentSpec(
      shape: widget.shape,
      width: values[0]!,
      depth: values[1]!,
      height: values[2]!,
      contour: List.of(points),
    );
    final invalid = spec.validate();
    if (invalid != null) {
      setState(() => error = invalid);
      return;
    }
    final request = revision;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final part = await compute(buildComponent, spec);
      if (mounted && request == revision) setState(() => created = part);
    } catch (e) {
      if (mounted && request == revision)
        setState(
          () => error = e is FormatException
              ? e.message
              : 'Bauteil konnte nicht erstellt werden.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    for (final c in dimensions) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Bauteil erstellen'),
      actions: [
        TextButton(
          onPressed: busy
              ? null
              : created == null
              ? create
              : () => Navigator.pop(context, created),
          child: Text(created == null ? 'Erstellen' : 'Übernehmen'),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          widget.chooser,
          const SizedBox(height: 20),
          StudioHeading(
            free ? 'Zeichne deine Bauteilkontur.' : 'Maße für dein Bauteil.',
            subtitle: switch (widget.shape) {
              ComponentShape.box =>
                'Quader als Vollkörper. Alle drei Außenmaße werden benötigt.',
              ComponentShape.oval => 'Gleiche Breite und Länge ergeben einen Kreis, unterschiedliche Maße ein Oval. Vollkörper.',
              _ => 'Die gezeichnete Kontur wird als Vollkörper über die gesamte Höhe fortgeführt. Auch L- und andere unregelmäßige Konturen sind möglich.',
            },
          ),
          if (free) ...[
            const Text(
              'Eckpunkte der Reihe nach antippen. Der letzte Punkt wird mit dem ersten verbunden. Die Zeichnung ist eine Draufsicht; Breite und Länge unten bestimmen die tatsächliche Größe.',
            ),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 1,
              child: LayoutBuilder(
                builder: (context, c) => GestureDetector(
                  key: const ValueKey('contour-canvas'),
                  onTapDown: busy
                      ? null
                      : (details) {
                          if (points.length >= 128) return;
                          final p = details.localPosition;
                          setState(() {
                            points.add(
                              Offset(
                                (p.dx / c.maxWidth).clamp(0.0, 1.0),
                                (1 - p.dy / c.maxHeight).clamp(0.0, 1.0),
                              ),
                            );
                            invalidate();
                          });
                        },
                  child: CustomPaint(
                    painter: _ContourPainter(List.of(points)),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: busy || points.isEmpty
                      ? null
                      : () => setState(() {
                          points.removeLast();
                          invalidate();
                        }),
                  icon: const Icon(Icons.undo),
                  label: const Text('Letzten Punkt entfernen'),
                ),
                TextButton(
                  onPressed: busy || points.isEmpty
                      ? null
                      : () => setState(() {
                          points.clear();
                          invalidate();
                        }),
                  child: const Text('Kontur löschen'),
                ),
              ],
            ),
          ] else ...[
            SizedBox(
              height: 150,
              child: CustomPaint(
                painter: _ShapePainter(widget.shape),
                child: const Center(
                  child: Text(
                    'Draufsicht\nBreite X ↔\nLänge Y ↕',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
            const Text(
              'Höhe Z: senkrecht zur Draufsicht, von der Unterseite bis zur Oberseite.',
            ),
            const SizedBox(height: 16),
          ],
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextField(
                key: ValueKey('component-dimension-$i'),
                controller: dimensions[i],
                enabled: !busy,
                keyboardType: TextInputType.text,
                onChanged: (_) => setState(invalidate),
                decoration: InputDecoration(
                  labelText: [
                    'Breite X (mm)',
                    'Länge Y (mm)',
                    'Höhe Z / Dicke (mm)',
                  ][i],
                  helperText: i == 2 && free
                      ? 'Abstand von Unterseite zu Oberseite, senkrecht zur Kontur.'
                      : 'Außenmaß, zum Beispiel 35 oder 3,5 cm',
                ),
              ),
            ),
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (created != null) ...[
            ComponentPreview(key: ObjectKey(created), part: created!),
            const SizedBox(height: 12),
            Text(
              'Außenmaße: ${created!.width} × ${created!.depth} × ${created!.height} mm',
            ),
            const Text(
              'Prüfe die Vorschau. Mit „Übernehmen“ öffnest du die Druckplatte und kannst die STL speichern.',
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'Für Aussparungen, Bohrungen oder unterschiedliche Querschnitte reicht diese Vollkörper-Vorlage noch nicht aus. Eine freie räumliche Form wird durch drei Außenmaße allein nicht beschrieben.',
            style: TextStyle(fontSize: 12, color: studioMuted),
          ),
        ],
      ),
    ),
  );
}

class _ContourPainter extends CustomPainter {
  const _ContourPainter(this.points);
  final List<Offset> points;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xfff2f0fa),
    );
    final grid = Paint()
      ..color = const Color(0xffd8d2e8)
      ..strokeWidth = 1;
    for (var i = 0; i <= 10; i++) {
      canvas.drawLine(
        Offset(i * size.width / 10, 0),
        Offset(i * size.width / 10, size.height),
        grid,
      );
      canvas.drawLine(
        Offset(0, i * size.height / 10),
        Offset(size.width, i * size.height / 10),
        grid,
      );
    }
    Offset p(Offset v) => Offset(v.dx * size.width, (1 - v.dy) * size.height);
    if (points.length > 1) {
      final path = Path()
        ..addPolygon(points.map(p).toList(), points.length >= 3);
      if (points.length >= 3)
        canvas.drawPath(path, Paint()..color = const Color(0x446550c7));
      canvas.drawPath(
        path,
        Paint()
          ..color = studioPurple
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(p(points[i]), 4, Paint()..color = studioPurple);
      final label = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: const TextStyle(color: Colors.black, fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, p(points[i]) + const Offset(5, 2));
    }
  }

  @override
  bool shouldRepaint(_ContourPainter old) => !listEquals(old.points, points);
}

class _ShapePainter extends CustomPainter {
  const _ShapePainter(this.shape);
  final ComponentShape shape;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: size.width * .75,
      height: size.height * .8,
    );
    final fill = Paint()..color = const Color(0xffded7ff),
        line = Paint()
          ..color = studioPurple
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
    if (shape == ComponentShape.box) {
      canvas.drawRect(rect, fill);
      canvas.drawRect(rect, line);
    } else {
      canvas.drawOval(rect, fill);
      canvas.drawOval(rect, line);
    }
  }

  @override
  bool shouldRepaint(_ShapePainter old) => old.shape != shape;
}
