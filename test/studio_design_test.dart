import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:print_optimizer/main.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(()async{
    final icons=FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final file=File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
    if(await file.exists()){
      final loader=FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(await file.readAsBytes())));
      await loader.load();
    }
  });
  for(final size in [const Size(390,844),const Size(840,900)]){
    testWidgets('Studio layout at ${size.width} keeps primary action and tools usable',(tester)async{
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize=size;tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      final boundary=GlobalKey();
      await tester.pumpWidget(RepaintBoundary(key:boundary,child:const OptimizerApp()));await tester.pumpAndSettle();
      expect(find.text('STL / 3MF öffnen'),findsOneWidget);expect(find.text('Deine Werkzeuge'),findsOneWidget);
      expect(tester.takeException(),isNull);
      if(size.width==390){
        await tester.runAsync(()async{
          final render=boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image=await render.toImage(pixelRatio:1);
          final bytes=await image.toByteData(format:ui.ImageByteFormat.png);image.dispose();
          if(bytes!=null)print('STUDIO_PHONE_PNG:${base64Encode(bytes.buffer.asUint8List())}');
        });
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
