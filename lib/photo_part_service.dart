import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'plate_geometry.dart';

class PhotoPartQuestion {
  PhotoPartQuestion(this.json);
  final Map<String,dynamic> json;
  String get id=>json['id'] as String;
  String get label=>json['label'] as String;
  String get help=>json['help'] as String;
  bool get isLength=>json['kind']=='mm';
  List<String> get choices=>List<String>.from(json['choices'] as List);
  int get imageIndex=>json['image_index'] as int;
  List<double> get a=>(json['a'] as List).map((v)=>(v as num).toDouble()).toList();
  List<double> get b=>(json['b'] as List).map((v)=>(v as num).toDouble()).toList();
}
class PhotoPartPlan {
  PhotoPartPlan._(this.json,this.questions);
  final Map<String,dynamic> json;
  final List<PhotoPartQuestion> questions;
  String get name=>json['name'] as String;
  String get summary=>json['summary'] as String;
  String get status=>json['status'] as String;
  List<String> get assumptions=>List<String>.from(json['assumptions'] as List);
  List<String> get blockers=>List<String>.from(json['blockers'] as List);
  static PhotoPartPlan parse(Map<String,dynamic> json,int imageCount,{PhotoPartPlan? previous}){
    if(imageCount<4||imageCount>8||!['ready','need_measurements','unsupported'].contains(json['status']))throw const FormatException('Ungültige Fotoanalyse.');
    for(final field in ['name','summary']){if(json[field] is! String||(json[field] as String).length>3000)throw const FormatException('Ungültige Analysebeschreibung.');}
    for(final field in ['assumptions','blockers']){final value=json[field];if(value is! List||value.length>32||value.any((v)=>v is! String||v.length>1000))throw const FormatException('Ungültige Analysehinweise.');}
    final raw=json['dimensions'];if(raw is! List||raw.length>32)throw const FormatException('Ungültige Maßfragen.');
    final questions=<PhotoPartQuestion>[],ids=<String>{};
    for(final value in raw){
      if(value is! Map)throw const FormatException('Ungültige Maßfrage.');
      final q=Map<String,dynamic>.from(value),id=q['id'];
      if(id is! String||!RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,47}$').hasMatch(id)||!ids.add(id))throw const FormatException('Ungültige oder doppelte Maß-ID.');
      if(!['mm','choice'].contains(q['kind'])||q['label'] is! String||q['help'] is! String||(q['label'] as String).isEmpty||(q['help'] as String).isEmpty||(q['label'] as String).length>1000||(q['help'] as String).length>1000)throw const FormatException('Ungültige Maßbeschreibung.');
      if(q['choices'] is! List||(q['choices'] as List).length>12||(q['choices'] as List).any((v)=>v is! String||v.length>200))throw const FormatException('Ungültige Auswahl.');
      final index=q['image_index'];if(index is! int||index< -1||index>=imageCount)throw const FormatException('Maßfrage verweist auf ein falsches Foto.');
      for(final key in ['a','b']){
        final points=q[key];if(points is! List||points.length!=(index==-1?0:2)||points.any((v)=>v is! num||!v.isFinite||v<0||v>1))throw const FormatException('Ungültige Messmarkierung.');
      }
      questions.add(PhotoPartQuestion(q));
    }
    if(previous!=null){for(final old in previous.questions){final current=questions.where((q)=>q.id==old.id).firstOrNull;
      if(current==null||current.label!=old.label||current.help!=old.help||current.isLength!=old.isLength||jsonEncode(current.choices)!=jsonEncode(old.choices))throw const FormatException('Die Analyse hat eine bestehende Maßfrage verändert.');
    }}
    if(json['operations'] is! List||(json['operations'] as List).length>96)throw const FormatException('Zu komplexe Geometriebeschreibung.');
    return PhotoPartPlan._(json,questions);
  }
}

double? photoLengthMillimetres(String text){
  final match=RegExp(r'^(\d+(?:[.,]\d+)?)\s*(mm|cm)?$',caseSensitive:false).firstMatch(text.trim());
  if(match==null)return null;
  final value=double.tryParse(match[1]!.replaceAll(',','.'));
  final mm=value==null?null:value*(match[2]?.toLowerCase()=='cm'?10:1);
  return mm!=null&&mm.isFinite&&mm>0&&mm<=10000?mm:null;
}

class PhotoPartService {
  PhotoPartService(this.base,this.accessCode){
    if(base.scheme!='https'||base.host.isEmpty||base.userInfo.isNotEmpty||base.hasQuery||base.hasFragment||base.path!=''&&base.path!='/')throw const FormatException('Eine HTTPS-Adresse ohne Pfad oder Zugangsdaten eintragen.');
    if(accessCode.length<32||accessCode.length>512||accessCode.contains(RegExp(r'[\r\n]')))throw const FormatException('Ungültiger Zugangscode des Fotodienstes.');
  }
  final Uri base;final String accessCode;
  HttpClient? _active;
  void cancel(){_active?.close(force:true);_active=null;}
  Future<Uint8List> _post(String path,Map<String,dynamic> value,int limit)async{
    final client=HttpClient()..connectionTimeout=const Duration(seconds:20);_active=client;
    try{
      final body=utf8.encode(jsonEncode(value));if(body.length>28*1024*1024)throw const FormatException('Fotos sind zusammen zu groß. Kleinere Bilder verwenden.');
      final request=await client.postUrl(base.resolve(path)).timeout(const Duration(seconds:25));
      request.followRedirects=false;request.headers.set(HttpHeaders.authorizationHeader,'Bearer $accessCode');
      request.headers.contentType=ContentType.json;request.add(body);
      final response=await request.close().timeout(const Duration(seconds:180));
      final bytes=BytesBuilder(copy:false);var count=0;
      await for(final chunk in response.timeout(const Duration(seconds:30))){count+=chunk.length;if(count>limit)throw const FormatException('Antwort des Fotodienstes ist zu groß.');bytes.add(chunk);}
      final data=bytes.takeBytes();
      if(response.statusCode!=200){
        String message='Fotodienst nicht erreichbar oder noch nicht eingerichtet.';
        if(data.length<12000){try{final v=jsonDecode(utf8.decode(data));if(v is Map&&v['error'] is String)message=(v['error'] as String).substring(0,math.min(1000,(v['error'] as String).length));}catch(_) {}}
        throw FormatException(message);
      }
      return data;
    }finally{client.close(force:true);if(identical(_active,client))_active=null;}
  }
  Future<PhotoPartPlan> analyze(List<Uint8List> images,Map<String,Object> answers,PhotoPartPlan? previous)async{
    if(images.length<4||images.length>8)throw const FormatException('Vier bis acht Fotos auswählen.');
    final data=await _post('/v1/analyze',{'images':images.map(base64Encode).toList(),'answers':answers,'previous':previous?.json},2*1024*1024);
    return PhotoPartPlan.parse(Map<String,dynamic>.from(jsonDecode(utf8.decode(data)) as Map),images.length,previous:previous);
  }
  Future<Uint8List> generate(PhotoPartPlan plan,Map<String,Object> answers,int imageCount,bool approved)async{
    if(plan.status!='ready'||plan.blockers.isNotEmpty||plan.questions.any((q)=>!answers.containsKey(q.id))||!plan.questions.any((q)=>q.isLength)||plan.assumptions.isNotEmpty&&!approved)throw const FormatException('Erst Maßfragen und Näherungen bestätigen.');
    return _post('/v1/generate',{'plan':plan.json,'answers':answers,'image_count':imageCount,'assumptions_accepted':approved},26*1024*1024);
  }
}

PlatePart photoPartFromStl(Uint8List bytes){
  if(bytes.length<84)throw const FormatException('Leere STL-Antwort.');
  final data=ByteData.sublistView(bytes),count=data.getUint32(80,Endian.little);
  if(count<4||count>500000||bytes.length!=84+count*50)throw const FormatException('Ungültige STL-Antwort.');
  final values=Float32List(count*9);final low=[double.infinity,double.infinity,double.infinity],high=[double.negativeInfinity,double.negativeInfinity,double.negativeInfinity];
  for(var t=0;t<count;t++)for(var i=0;i<9;i++){
    final value=data.getFloat32(84+t*50+12+i*4,Endian.little);
    if(!value.isFinite||value.abs()>10000)throw const FormatException('Ungültige Modellkoordinaten.');
    values[t*9+i]=value;final axis=i%3;low[axis]=math.min(low[axis],value);high[axis]=math.max(high[axis],value);
  }
  final dimensions=List.generate(3,(i)=>high[i]-low[i]);
  if(dimensions.any((v)=>v<=0||v>2000))throw const FormatException('Ungültige Modellausdehnung.');
  final unit=math.sqrt(dimensions.fold<double>(0,(sum,v)=>sum+v*v))/2;
  for(var i=0;i<values.length;i++)values[i]=(values[i]-(low[i%3]+high[i%3])/2)/unit;
  return PlatePart(name:'Foto_Bauteil.stl',vertices:values,unitScale:unit,width:dimensions[0],depth:dimensions[1],height:dimensions[2]);
}
