import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:print_optimizer/help_chat.dart';

void main(){
  testWidgets('Web search only opens on request and preserves the current or last question',(tester)async{
    final opened=<Uri>[];
    await tester.pumpWidget(MaterialApp(home:HelpChatPage(openSearch:(uri)async{opened.add(uri);return true;})));
    await tester.enterText(find.byType(TextField),'PETG außen & Wärme?');
    expect(opened,isEmpty);
    await tester.tap(find.byTooltip('Im Web suchen'));await tester.pumpAndSettle();
    expect(opened.single.scheme,'https');expect(opened.single.host,'www.google.com');
    expect(opened.single.queryParameters['q'],'3D Druck PETG außen & Wärme?');
    await tester.tap(find.byTooltip('Frage senden'));await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Im Web suchen'));await tester.pumpAndSettle();
    expect(opened.length,2);expect(opened.last,opened.first);
    expect(find.text('Offline-Hilfe · Websuche öffnet deinen Browser'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
  testWidgets('Empty search cannot launch an external page',(tester)async{
    var calls=0;
    await tester.pumpWidget(MaterialApp(home:HelpChatPage(openSearch:(uri)async{calls++;return true;})));
    await tester.tap(find.byTooltip('Im Web suchen'));await tester.pumpAndSettle();
    expect(calls,0);expect(find.text('Zuerst eine Frage eingeben.'),findsOneWidget);
  });
}
