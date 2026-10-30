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
