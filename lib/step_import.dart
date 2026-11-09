import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

const maxStepBytes=20*1024*1024;
const maxStepMeshBytes=25000084;
bool isStepFile(String name)=>RegExp(r'\.(step|stp)$',caseSensitive:false).hasMatch(name);
void validateStepInput(Uint8List bytes){
  if(bytes.length<20||bytes.length>maxStepBytes)throw const FormatException('STEP-Dateien bis 20 MB werden unterstützt.');
  final start=bytes[0]==239&&bytes[1]==187&&bytes[2]==191?3:0;
  final header=ascii.decode(bytes.sublist(start,math.min(bytes.length,128)),allowInvalid:true).trimLeft();
  if(!header.startsWith('ISO-10303-21;'))throw const FormatException('Keine gültige STEP-Datei gefunden.');
}

/// Acknowledged chunks keep the browser/native message queue bounded.
class StepMeshBuffer {
  int? expected;
  int received=0;
  bool complete=false;
  final _bytes=BytesBuilder(copy:false);
  void begin(Object? count){
    if(expected!=null||count is! int||count<134||count>maxStepMeshBytes)throw const FormatException('STEP-Modell ist zu groß oder enthält keine Flächen.');
    expected=count;
  }
  void add(Object? offset,Object? encoded){
    if(complete||expected==null||offset!=received||encoded is! String||encoded.isEmpty||encoded.length>32768)throw const FormatException('STEP-Übertragung ist unvollständig.');
    final chunk=base64Decode(encoded);
    if(chunk.isEmpty||chunk.length>24576||received+chunk.length>expected!)throw const FormatException('STEP-Übertragung ist ungültig.');
    _bytes.add(chunk);received+=chunk.length;
  }
  Uint8List finish(){
    if(complete||expected==null||received!=expected)throw const FormatException('STEP-Modell wurde nicht vollständig umgewandelt.');
    complete=true;
    final bytes=_bytes.takeBytes();
    // Validate the binary STL envelope independently of the JavaScript adapter.
    final count=ByteData.sublistView(bytes).getUint32(80,Endian.little);
    if(count==0||84+count*50!=bytes.length)throw const FormatException('STEP-Modell enthält kein gültiges Dreiecksnetz.');
    return bytes;
  }
}

Future<Uint8List?> importStep(BuildContext context,Uint8List bytes,String name)async{
  validateStepInput(bytes);
  if(!Platform.isAndroid&&!Platform.isIOS&&!Platform.isMacOS)throw const FormatException('STEP-Import ist in dieser Version für Android verfügbar.');
  return Navigator.push<Uint8List>(context,MaterialPageRoute(builder:(_)=>StepImportPage(bytes:bytes,name:name)));
}

class StepImportPage extends StatefulWidget {
  const StepImportPage({super.key,required this.bytes,required this.name});
  final Uint8List bytes;final String name;
  @override State<StepImportPage> createState()=>_StepImportPageState();
}
class _StepImportPageState extends State<StepImportPage>{
  late final WebViewController controller;
  final buffer=StepMeshBuffer();
  Timer? timer;bool started=false,finished=false;
  String? error;
  @override void initState(){
    super.initState();
    controller=WebViewController()..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('StepBridge',onMessageReceived:(message){messageReceived(message.message);})
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest:(request){final uri=Uri.tryParse(request.url);return uri!=null&&uri.scheme=='file'&&uri.host.isEmpty&&uri.path.endsWith('/assets/step/index.html')?NavigationDecision.navigate:NavigationDecision.prevent;},
        onWebResourceError:(value){if(value.isForMainFrame==true)fail('Die lokale STEP-Komponente konnte nicht gestartet werden.');},
      ));
    timer=Timer(const Duration(minutes:2),()=>fail('Die STEP-Umwandlung dauert zu lange. Datei vereinfachen und erneut versuchen.'));
    controller.loadFlutterAsset('assets/step/index.html').catchError((_)=>fail('Die lokale STEP-Komponente fehlt. Bitte die App aktualisieren.'));
  }
  void fail(String message){
    if(!mounted||finished)return;
    finished=true;timer?.cancel();
    controller.runJavaScript('window.stepCancel && window.stepCancel()').catchError((_){ });
    setState(()=>error=message);
  }
  Future<void> sendInput()async{
    if(started||finished)return;started=true;
    await controller.runJavaScript('window.stepBegin(${widget.bytes.length})');
    for(var offset=0;offset<widget.bytes.length;offset+=24576){
      if(!mounted||finished)return;
      final end=math.min(offset+24576,widget.bytes.length);
      final encoded=base64Encode(Uint8List.sublistView(widget.bytes,offset,end));
      await controller.runJavaScript('window.stepAppend(${jsonEncode(encoded)})');
    }
    if(mounted&&!finished)await controller.runJavaScript('window.stepConvert()');
  }
  Future<void> messageReceived(String text)async{
    if(!mounted||finished)return;
    try{
      if(text.length>65536)throw const FormatException();
      final value=jsonDecode(text);if(value is! Map)throw const FormatException();
      switch(value['type']){
        case 'ready':await sendInput();break;
        case 'begin':buffer.begin(value['bytes']);await controller.runJavaScript('window.stepReadNext()');break;
        case 'chunk':buffer.add(value['offset'],value['data']);await controller.runJavaScript('window.stepReadNext()');break;
        case 'done':
          final result=buffer.finish();finished=true;timer?.cancel();
          if(mounted)Navigator.pop(context,result);break;
        case 'error':fail(value['code']=='STEP_COMPLEX'?'Das STEP-Modell ist zu komplex. Bitte mit weniger Details exportieren.':'Die STEP-Datei konnte nicht in ein Dreiecksnetz umgewandelt werden.');break;
        default:throw const FormatException();
      }
    }catch(_){fail('Die STEP-Umwandlung konnte nicht vollständig abgeschlossen werden.');}
  }
  @override void dispose(){
    finished=true;timer?.cancel();
    controller.runJavaScript('window.stepCancel && window.stepCancel()').catchError((_){ });
    super.dispose();
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('STEP öffnen')),
    body:SafeArea(child:Padding(padding:const EdgeInsets.all(24),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(widget.name,style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:24),
      if(error==null)...[const CircularProgressIndicator(),const SizedBox(height:24),const Text('CAD-Flächen werden für Vorschau und Druck umgewandelt.'),const SizedBox(height:12),const Text('Verarbeitung auf diesem Gerät · Maße in Millimetern')]
      else Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
      const SizedBox(height:24),OutlinedButton(onPressed:()=>Navigator.pop(context),child:Text(error==null?'Abbrechen':'Zurück')),
      SizedBox(width:1,height:1,child:WebViewWidget(controller:controller)),
    ]))),
  );
}
