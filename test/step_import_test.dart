import 'dart:convert';
import 'package:print_optimizer/main.dart' show readPlateModel;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:print_optimizer/step_import.dart';

Uint8List triangle(){
  final bytes=Uint8List(134);ByteData.sublistView(bytes).setUint32(80,1,Endian.little);return bytes;
}
void main(){
  test('Converted STEP mesh enters the actual plate importer with millimetre dimensions',(){
    // Public simple-basic-cube fixture converted by the pinned OCCT engine.
    final bytes=base64Decode('M0QgUHJpbnQgT3B0aW1pemVyIC0gU1RFUCBjb252ZXJ0ZWQgdG8gbWlsbGltZXRyZXMAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAMAAAAAACAPwAAAAAAAAAAAAAMQwAAIEMAAJZDAAAMQwAADMMAAJZDAAAMQwAADMMAAAAAAAAAAIA/AAAAAAAAAAAAAAxDAAAgQwAAlkMAAAxDAAAMwwAAAAAAAAxDAAAgQwAAAAAAAAAAAAAAAIA/AAAAgAAADEMAACBDAAAAAAAAIMMAACBDAACWQwAADEMAACBDAACWQwAAAAAAAAAAgD8AAAAAAAAMQwAAIEMAAAAAAAAgwwAAIEMAAAAAAAAgwwAAIEMAAJZDAAAAAIC/7+5uJwAAAAAAACDDAAAgQwAAlkMAACDDAAAMwwAAAAAAACDDAAAMwwAAlkMAAAAAgL/v7m4nAAAAAAAAIMMAACBDAACWQwAAIMMAACBDAAAAAAAAIMMAAAzDAAAAAAAAAAAAAAAAgL8AAAAAAAAgwwAADMMAAAAAAAAMQwAADMMAAAAAAAAMQwAADMMAAJZDAAAAAAAAAACAvwAAAAAAACDDAAAMwwAAlkMAACDDAAAMwwAAAAAAAAxDAAAMwwAAlkMAAAAAAAAAAAAAAACAPwAAIMMAACBDAACWQwAAIMMAAAzDAACWQwAADEMAAAzDAACWQwAAAAAAAAAAAAAAAIA/AAAMQwAAIEMAAJZDAAAgwwAAIEMAAJZDAAAMQwAADMMAAJZDAAAAAAAAAAAAAAAAgL8AAAxDAAAMwwAAAAAAACDDAAAMwwAAAAAAACDDAAAgQwAAAAAAAAAAAIAAAACAAACAvwAADEMAACBDAAAAAAAADEMAAAzDAAAAAAAAIMMAACBDAAAAAAAA');
    final part=readPlateModel(('cube.step',bytes));
    expect(part.vertices,isNotEmpty);
    expect(part.width,closeTo(300,0.001));expect(part.depth,closeTo(300,0.001));expect(part.height,closeTo(300,0.001));
  });

  test('STEP/STP extensions and Part 21 headers including a UTF8 BOM are accepted',(){
    for(final name in ['Zaun.step','Teil.STP','Baugruppe.STEP'])expect(isStepFile(name),true);
    for(final name in ['Teil.stl','Teil.step.exe','test'])expect(isStepFile(name),false);
    validateStepInput(Uint8List.fromList(utf8.encode('ISO-10303-21;\nHEADER;\nENDSEC;')));
    validateStepInput(Uint8List.fromList([239,187,191,...utf8.encode('ISO-10303-21;\nHEADER;\nENDSEC;')]));
    expect(()=>validateStepInput(Uint8List.fromList(utf8.encode('not a STEP file at all'))),throwsFormatException);
    expect(()=>validateStepInput(Uint8List(maxStepBytes+1)),throwsFormatException);
  });
  test('Acknowledged chunks preserve bytes across boundaries and reject truncation and reuse',(){
    final bytes=triangle(),buffer=StepMeshBuffer()..begin(bytes.length);
    buffer.add(0,base64Encode(bytes.sublist(0,73)));
    expect(()=>buffer.finish(),throwsFormatException);
    expect(()=>buffer.add(0,base64Encode(bytes.sublist(73))),throwsFormatException);
    buffer.add(73,base64Encode(bytes.sublist(73)));
    expect(buffer.finish(),bytes);
    expect(()=>buffer.finish(),throwsFormatException);
    expect(()=>buffer.add(134,'AAAA'),throwsFormatException);
  });
  test('Malformed output and excessive or repeated allocation declarations fail',(){
    expect(()=>StepMeshBuffer().begin(maxStepMeshBytes+1),throwsFormatException);
    expect(()=>StepMeshBuffer().begin(-1),throwsFormatException);
    final buffer=StepMeshBuffer()..begin(134);
    expect(()=>buffer.begin(134),throwsFormatException);
    expect(()=>buffer.add(0,'?'*33000),throwsFormatException);
    final invalid=triangle();ByteData.sublistView(invalid).setUint32(80,2,Endian.little);
    buffer.add(0,base64Encode(invalid));expect(()=>buffer.finish(),throwsFormatException);
  });
}
