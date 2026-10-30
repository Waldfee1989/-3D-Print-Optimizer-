import 'adapter_geometry.dart';

class AdapterRequest {
  const AdapterRequest(this.ports,{this.length,this.wall,this.socket});
  final List<AdapterPort> ports;final double? length,wall,socket;
}
String normalizeAdapterSpeech(String value){
  var text=value.toLowerCase().replaceAll('ä','ae').replaceAll('ö','oe').replaceAll('ü','ue').replaceAll('ß','ss');
  const units=['null','eins','zwei','drei','vier','fuenf','sechs','sieben','acht','neun'];
  const small=['zehn','elf','zwoelf','dreizehn','vierzehn','fuenfzehn','sechzehn','siebzehn','achtzehn','neunzehn'];
  const tens=['','','zwanzig','dreissig','vierzig','fuenfzig','sechzig','siebzig','achtzig','neunzig'];
  final words=<String,int>{for(var i=0;i<10;i++)units[i]:i,'ein':1};
  for(var i=10;i<20;i++){words[small[i-10]]=i;}
  for(var t=2;t<10;t++){
    words[tens[t]]=t*10;
    for(var u=1;u<10;u++){words['${u==1?'ein':units[u]}und${tens[t]}']=t*10+u;}
  }
  text=text.replaceAllMapped(RegExp(r'\b(ein|eins|zwei|drei|vier|fuenf|sechs|sieben|acht|neun)\s+und\s+(zwanzig|dreissig|vierzig|fuenfzig|sechzig|siebzig|achtzig|neunzig)\b'),
    (m)=>'${m[1]=='eins'?'ein':m[1]}und${m[2]}');
  text=text.replaceAllMapped(RegExp(r'\b[a-z]+\b'),(m){
    final word=m[0]!;if(words.containsKey(word))return '${words[word]}';
    final hundred=word.indexOf('hundert');
    if(hundred>=0){final prefix=word.substring(0,hundred),tail=word.substring(hundred+7);final h=prefix.isEmpty?1:words[prefix];
      final rest=tail.isEmpty?0:words[tail];if(h!=null&&h>0&&h<10&&rest!=null)return '${h*100+rest}';}
    return word;
  });
  text=text.replaceAllMapped(RegExp(r'(\d+)\s+komma\s+((?:\d+\s*)+)'),(m)=>'${m[1]}.${m[2]!.replaceAll(RegExp(r'\s+'),'')}');
  return text.replaceAll(',','.');
}
AdapterRequest parseAdapterRequest(String input){
  final text=normalizeAdapterSpeech(input);
  const type=r'(innendurchmesser|innen\s*durchmesser|innen|aussendurchmesser|aussen\s*durchmesser|aussen)';
  const number=r'(\d+(?:\.\d+)?)';
  const unit=r'(millimeter|zentimeter|mm|cm)?';
  final hits=<(int,int,AdapterPort)>[];
  double value(String n,String? u)=>double.parse(n)*(u=='cm'||u=='zentimeter'?10:1);
  final forward=RegExp('$type\\s*(?:von|mit|ist|:|=)?\\s*$number\\s*$unit');
  for(final m in forward.allMatches(text)){
    hits.add((m.start,m.end,AdapterPort(m[1]!.startsWith('innen')?DiameterKind.inner:DiameterKind.outer,value(m[2]!,m[3]))));
  }
  final reverse=RegExp('$number\\s*$unit\\s*$type');
  for(final m in reverse.allMatches(text)){
    if(hits.any((h)=>m.start<h.$2&&m.end>h.$1))continue;
    hits.add((m.start,m.end,AdapterPort(m[3]!.startsWith('innen')?DiameterKind.inner:DiameterKind.outer,value(m[1]!,m[2]))));
  }
  hits.sort((a,b)=>a.$1.compareTo(b.$1));
  double? dimension(String label){
    final direct=RegExp('(?:$label)\\s*(?:von|mit|ist|:|=)?\\s*$number\\s*$unit').firstMatch(text);
    if(direct!=null)return value(direct[1]!,direct[2]);
    final reversed=RegExp('$number\\s*$unit\\s*(?:$label)').firstMatch(text);
    return reversed==null?null:value(reversed[1]!,reversed[2]);
  }
  return AdapterRequest(hits.map((h)=>h.$3).toList(),length:dimension('laenge|lang|gesamtlaenge'),wall:dimension('wandstaerke|wanddicke'),socket:dimension('stecktiefe'));
}

enum AdapterField { first,second,length,wall,socket }
class AdapterDraft {
  AdapterPort? first,second;
  double? length,wall,socket;
  List<AdapterField> get missing=>[
    if(first==null)AdapterField.first,if(second==null)AdapterField.second,
    if(length==null)AdapterField.length,if(wall==null)AdapterField.wall,if(socket==null)AdapterField.socket,
  ];
  AdapterField? get next=>missing.isEmpty?null:missing.first;
  bool get complete=>missing.isEmpty;
  String get question=>switch(next){
    AdapterField.first=>'Welchen Durchmesser braucht Seite A? Innen oder außen?',
    AdapterField.second=>'Welchen Durchmesser braucht Seite B? Innen oder außen?',
    AdapterField.length=>'Wie lang soll das Bauteil insgesamt sein? Angabe in Millimetern.',
    AdapterField.wall=>'Welche Wandstärke sollen die Öffnungen haben? Angabe in Millimetern.',
    AdapterField.socket=>'Wie lang soll der gerade Steckbereich je Seite sein? Angabe in Millimetern.',
    null=>'Sind diese Maße richtig?',
  };
  void clear(AdapterField field){switch(field){
    case AdapterField.first:first=null;
    case AdapterField.second:second=null;
    case AdapterField.length:length=null;
    case AdapterField.wall:wall=null;
    case AdapterField.socket:socket=null;
  }}
  void apply(AdapterRequest request){
    if(request.ports.length==2){first=request.ports[0];second=request.ports[1];}
    else if(request.ports.length==1){if(first==null){first=request.ports[0];}else if(second==null){second=request.ports[0];}}
    if(request.length!=null)length=request.length;if(request.wall!=null)wall=request.wall;if(request.socket!=null)socket=request.socket;
  }
  bool answer(String text,{DiameterKind? kind}){
    final field=next,before=missing.length,request=parseAdapterRequest(text);
    if(request.ports.length>2)return false;
    apply(request);
    if(field!=null&&missing.contains(field)){
      final normalized=normalizeAdapterSpeech(text).trim();
      final match=RegExp(r'^(\d+(?:\.\d+)?)\s*(mm|millimeter|cm|zentimeter)?$').firstMatch(normalized);
      final number=match==null?null:double.parse(match[1]!)*(match[2]=='cm'||match[2]=='zentimeter'?10:1);
      if(number!=null&&number>0&&number.isFinite){switch(field){
        case AdapterField.first:if(kind!=null)first=AdapterPort(kind,number);
        case AdapterField.second:if(kind!=null)second=AdapterPort(kind,number);
        case AdapterField.length:length=number;
        case AdapterField.wall:wall=number;
        case AdapterField.socket:socket=number;
      }}
    }
    return missing.length<before;
  }
  AdapterSpec spec(){
    if(!complete)throw const FormatException('Es fehlen noch Maße.');
    return AdapterSpec(first:first!,second:second!,length:length!,wall:wall!,socket:socket!);
  }
}
