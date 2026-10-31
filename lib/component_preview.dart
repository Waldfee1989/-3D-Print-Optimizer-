import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'plate_geometry.dart';
import 'mesh_renderer.dart';

class ComponentPreview extends StatefulWidget {
  const ComponentPreview({required this.part});
  final PlatePart part;
  @override
  State<ComponentPreview> createState() => ComponentPreviewState();
}

class ComponentPreviewState extends State<ComponentPreview> {
  ui.Image? image;
  double x = 25, y = 30;
  int revision = 0;
  bool rendering = false;
  @override
  void initState() {
    super.initState();
    render();
  }

  Future<void> render() async {
    revision++;
    if (rendering) return;
    rendering = true;
    try {
      while (mounted) {
        final request = revision,
            pixels = await compute(
              renderMesh,
              MeshRenderRequest(widget.part.vertices, 300, 300, x, y, 1),
            );
        if (!mounted) return;
        final complete = Completer<ui.Image>();
        ui.decodeImageFromPixels(
          pixels,
          300,
          300,
          ui.PixelFormat.rgba8888,
          complete.complete,
        );
        final next = await complete.future;
        if (!mounted || request != revision) {
          next.dispose();
          if (!mounted) return;
          continue;
        }
        final old = image;
        setState(() => image = next);
        if (old != null)
          WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
        break;
      }
    } finally {
      rendering = false;
    }
  }

  @override
  void dispose() {
    image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(24),
    child: Container(
      height: 280,
      color: const Color(0xff1c1a2d),
      child: RawGestureDetector(
        gestures: {
          EagerGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                () => EagerGestureRecognizer(),
                (_) {},
              ),
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerMove: (event) {
            x = (x + event.delta.dy).clamp(-180.0, 180.0).toDouble();
            y = (y + event.delta.dx).clamp(-180.0, 180.0).toDouble();
            render();
          },
          child: image == null
              ? const Center(child: CircularProgressIndicator())
              : RawImage(image: image, fit: BoxFit.contain),
        ),
      ),
    ),
  );
}
