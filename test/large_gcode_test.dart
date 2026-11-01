import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:print_optimizer/gcode_preview.dart';
import 'package:print_optimizer/printer_setup.dart';

void main(){
  const bed=PrinterBed(250,250,250);
  late Directory directory;
  setUp(()async{directory=await Directory.systemTemp.createTemp('large-gcode-test-');});
  tearDown(()async{await directory.delete(recursive:true);});
  test('A real file above 128 MiB is streamed to its final move and checked completely',()async{
    final file=File('${directory.path}/large.gcode'),out=await File('${directory.path}/large.gcode').open(mode:FileMode.write);
    await out.writeString(';TIME:42\n;LAYER:0\nG90\nM83\nG1 X10 Y10 Z0.2 E1\n');
    final block=utf8.encode(List.filled(1024,';${'x'*1022}\n').join());
    for(var i=0;i<129;i++){await out.writeFrom(block);}
    await out.writeString('; große Datei\n;LAYER:1\nG1 X251 Y20 Z0.4 E1');await out.close();
    expect(await file.length(),greaterThan(128*1024*1024));
    final result=await parseGcodeFile((file.path,bed));
    expect(result.layers.length,2);expect(result.extrusionMoves,2);expect(result.seconds,42);
    expect(result.outsideBed,isTrue);expect(result.layers.last.segments.last,0);
  },timeout:const Timeout(Duration(minutes:2)));
  test('Dense files bound preview geometry but still count and validate omitted moves',(){
    final source=StringBuffer(';LAYER:0\nG90\nM83\nG1 X10 Y10 Z0.2 E1\n');
    for(var i=0;i<320001;i++){source.writeln('G1 X${i.isEven?20:10} E1');}
    source.write('G1 X251 E1\nG1 X20 E1\n;LAYER:1\nG1 X10 Z0.4 E1');
    final result=parseGcode((source.toString(),bed));
    expect(result.simplified,isTrue);expect(result.outsideBed,isTrue);
    expect(result.extrusionMoves,320005);expect(result.layers.length,2);
    expect(result.layers.last.segments,isNotEmpty);
    expect(result.layers.fold<int>(0,(n,l)=>n+l.segments.length~/5),lessThanOrEqualTo(maxPreviewSegments));
  });
  test('Streaming preserves small-file results, unicode comments and a final line without newline',()async{
    const source=';TIME:123\r\n;Filament used:0.1m\n;LAYER:0\n; Grüße\nG90\nM83\nG1 X10 Y10 Z0.2 E1\nG91\nG1 X5 E1';
    final file=await File('${directory.path}/small.gcode').writeAsString(source);
    final actual=await parseGcodeFile((file.path,bed)),expected=parseGcode((source,bed));
    expect(actual.layers.single.segments,expected.layers.single.segments);
    expect(actual.extrusionMoves,expected.extrusionMoves);expect(actual.outsideBed,expected.outsideBed);
    expect(actual.filamentMetres,expected.filamentMetres);expect(actual.simplified,isFalse);
  });
  test('Oversize sparse files and pathological long lines fail before allocating whole file',()async{
    final file=File('${directory.path}/invalid.gcode'),out=await File('${directory.path}/invalid.gcode').open(mode:FileMode.write);
    await out.truncate(maxGcodeBytes+1);await out.close();
    await expectLater(parseGcodeFile((file.path,bed)),throwsFormatException);
    await file.writeAsString(';${'x'*70000}');
    await expectLater(parseGcodeFile((file.path,bed)),throwsFormatException);
  });
}
