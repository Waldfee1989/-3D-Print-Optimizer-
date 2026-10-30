import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// Page scrolling must not drag inside the model's gesture/rotation region.
Future<void> reveal(WidgetTester tester,Finder target) async {
  final scroll=tester.state<ScrollableState>(find.byType(Scrollable).first);
  scroll.position.jumpTo(0);await tester.pump();
  for(var attempt=0;attempt<100;attempt++){
    if(target.evaluate().isNotEmpty){
      await tester.ensureVisible(target);await tester.pumpAndSettle();
      final rect=tester.getRect(target);
      final height=tester.view.physicalSize.height/tester.view.devicePixelRatio;
      if(rect.center.dy>=0&&rect.center.dy<height)return;
    }
    final next=math.min(scroll.position.maxScrollExtent,scroll.position.pixels+180);
    if(next==scroll.position.pixels)break;
    scroll.position.jumpTo(next);await tester.pump();
  }
  throw TestFailure('Control not reachable: $target');
}
