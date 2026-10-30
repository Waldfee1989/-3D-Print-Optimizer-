import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:print_optimizer/adapter_geometry.dart';
import 'package:print_optimizer/adapter_request.dart';
import 'package:print_optimizer/support_analysis.dart';

void main(){
  test('German request preserves inside 35 and outside 50 in spoken order',(){
    for(final text in [
      'Ich brauche einen Adapter mit Innendurchmesser von 35 mm auf einer Seite und Außendurchmesser von 50 mm auf der anderen Seite',
      'Innendurchmesser fünfunddreißig Millimeter und außen fünfzig Millimeter',
      '35 mm innen und 5 cm außen',
    ]){
      final request=parseAdapterRequest(text);expect(request.ports.length,2);
      expect(request.ports[0].kind,DiameterKind.inner);expect(request.ports[0].diameter,35);
      expect(request.ports[1].kind,DiameterKind.outer);expect(request.ports[1].diameter,50);
    }
  });
  test('Decimal speech, wall, length and socket depth are separate dimensions',(){
    final request=parseAdapterRequest('innen fünfunddreißig Komma fünf mm, außen fünfzig mm, Länge sechzig mm, Wandstärke zwei Komma fünf mm und Stecktiefe fünfzehn mm');
    expect(request.ports[0].diameter,35.5);expect(request.wall,2.5);expect(request.length,60);expect(request.socket,15);
    expect(parseAdapterRequest('Adapter 35 auf 50').ports,isEmpty);
  });
  test('Missing dimensions produce targeted questions without silent defaults',(){
    final draft=AdapterDraft();
    expect(draft.answer('innen 35 mm und außen 50 mm'),isTrue);
    expect(draft.next,AdapterField.length);expect(draft.wall,isNull);expect(draft.socket,isNull);
    expect(()=>draft.spec(),throwsFormatException);
    draft.answer('sechzig Millimeter');expect(draft.next,AdapterField.wall);
    draft.answer('zwei Komma fünf Millimeter');expect(draft.next,AdapterField.socket);
    draft.answer('fünfzehn mm');expect(draft.complete,isTrue);
    expect(draft.spec().length,60);expect(draft.spec().wall,2.5);expect(draft.spec().socket,15);
    draft.clear(AdapterField.first);expect(draft.answer('35 mm'),isFalse);
    expect(draft.answer('35 mm',kind:DiameterKind.inner),isTrue);
  });
  test('Adapter is a closed hollow solid with the requested end diameters',(){
    final model=buildAdapter(const AdapterSpec(first:AdapterPort(DiameterKind.inner,35),second:AdapterPort(DiameterKind.outer,50)));
    expect(model.width,50);expect(model.height,60);expect(assessSupports(model.vertices).valid,isTrue);
    final radiiA=<double>[],radiiB=<double>[];
    for(var i=0;i<model.vertices.length;i+=3){
      final z=model.vertices[i+2]*model.unitScale,r=math.sqrt(model.vertices[i]*model.vertices[i]+model.vertices[i+1]*model.vertices[i+1])*model.unitScale;
      if((z+30).abs()<1e-4)radiiA.add(r);if((z-30).abs()<1e-4)radiiB.add(r);
    }
    expect(radiiA.reduce(math.min),closeTo(17.5,1e-4));expect(radiiA.reduce(math.max),closeTo(20,1e-4));
    expect(radiiB.reduce(math.min),closeTo(22.5,1e-4));expect(radiiB.reduce(math.max),closeTo(25,1e-4));
  });
  test('Impossible bores and overlapping sockets are rejected',(){
    expect(()=>buildAdapter(const AdapterSpec(first:AdapterPort(DiameterKind.outer,4),second:AdapterPort(DiameterKind.outer,50))),throwsFormatException);
    expect(()=>buildAdapter(const AdapterSpec(first:AdapterPort(DiameterKind.inner,35),second:AdapterPort(DiameterKind.outer,50),length:25)),throwsFormatException);
  });
}
