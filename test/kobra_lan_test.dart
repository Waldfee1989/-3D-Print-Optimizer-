import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:print_optimizer/kobra_lan.dart';

void main() {
  test('Only private literal printer IPv4 addresses are accepted', () {
    for (final ip in ['192.168.1.50', '10.0.0.5', '172.16.0.2', '172.31.1.9']) {
      expect(kobraLanIp(ip), ip);
    }
    for (final ip in ['127.0.0.1', '8.8.8.8', '172.32.0.2', '169.254.1.2', 'printer.local', 'https://192.168.1.2', '192.168.1.255', '::1', '192.168.1.4:18910']) {
      expect(() => kobraLanIp(ip), throwsFormatException);
    }
  });
  test('Upload address cannot redirect file data or include credentials', () {
    expect(kobraUploadUri('192.168.1.50', 'http://192.168.1.50:18910/gcode_upload?s=example').path, '/gcode_upload');
    for (final url in [null, 'http://8.8.8.8:18910/gcode_upload', 'http://192.168.1.50:80/gcode_upload', 'http://user:pass@192.168.1.50:18910/gcode_upload', 'http://192.168.1.50:18910/ctrl']) {
      expect(() => kobraUploadUri('192.168.1.50', url), throwsFormatException);
    }
    expect(kobraFilename('../../Name\r\n"with spaces'), matches(RegExp(r'^[A-Za-z0-9_-]+\.gcode$')));
  });

  late HttpServer server;
  late Directory directory;
  late File file;
  late KobraLanClient client;
  final requests = <String>[];
  var code = 200, model = '20025', infoCount = 0;
  String? uploadOverride;
  String? uploaded;
  String? xLength;
  String? contentType;
  int? httpError;
  bool missingCode = false;
  bool redirect = false, hold = false;
  Completer<void>? holdGate, requestSeen;
  final content = utf8.encode('; test-only toolpath\nG90\nG1 X10 Y20\n');
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('optimizer-lan-test-');
    file = await File('${directory.path}/sample.gcode').writeAsBytes(content);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = KobraLanClient.test('127.0.0.1', server.port);
    requests.clear(); code = 200; model = '20025'; infoCount = 0;
    uploadOverride = null; uploaded = null; httpError = null; missingCode = false;
    redirect = false; hold = false; holdGate = Completer<void>(); requestSeen = Completer<void>();
    server.listen((request) async {
      try {
      requests.add('${request.method} ${request.uri.path}');
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/info') {
        if (!requestSeen!.isCompleted) requestSeen!.complete();
        if (hold) await holdGate!.future;
        if (redirect) {
          request.response.statusCode = 302;
          request.response.headers.set('location', 'http://8.8.8.8/');
          await request.response.close(); return;
        }
        infoCount++;
        request.response.write(jsonEncode({'code': 200, 'data': {'modelId': model, 'urls': {
          'fileUploadurl': uploadOverride ?? 'http://127.0.0.1:${server.port}/gcode_upload?s=private_session_$infoCount'
        }}}));
      } else {
        xLength = request.headers.value('X-File-Length');
        contentType = request.headers.contentType.toString();
        expect(request.uri.queryParameters['s'], 'private_session_$infoCount');
        uploaded = await utf8.decoder.bind(request).join();
        if (httpError != null) request.response.statusCode = httpError!;
        request.response.write(jsonEncode(missingCode ? {'message': 'ambiguous'} : {'code': code, 'data': {'gcode': 'test.gcode'}}));
      }
      await request.response.close();
      } on SocketException { /* Expected if the test cancels its request. */
      } on HttpException { /* The peer may close while a held response is released. */ }
    });
  });
  tearDown(() async { client.cancel(); if (!holdGate!.isCompleted) holdGate!.complete(); await server.close(force: true); await directory.delete(recursive: true); });
  test('Upload refreshes token, streams unchanged bytes and waits for acknowledgment', () async {
    await client.inspect();
    final progress = <int>[];
    expect(await client.upload(file, 'test.gcode', progress: (sent, total) { expect(total, content.length); progress.add(sent); }), 'test.gcode');
    expect(infoCount, 2);
    expect(requests, ['GET /info', 'GET /info', 'POST /gcode_upload']);
    expect(xLength, '${content.length}'); expect(contentType, contains('multipart/form-data'));
    expect(uploaded, contains('name="filename"\r\n\r\ntest.gcode'));
    expect(uploaded, contains('name="gcode"; filename="test.gcode"'));
    expect(uploaded, contains(utf8.decode(content)));
    expect(progress.first, 0); expect(progress.last, content.length);
    expect(await file.readAsBytes(), content);
  });
  test('Wrong printer is refused before upload', () async {
    model = '20029';
    await expectLater(client.upload(file, 'test.gcode'), throwsFormatException);
    expect(requests, ['GET /info']);
  });
  test('Cross-origin printer URL is refused before sending bytes', () async {
    uploadOverride = 'http://8.8.8.8:18910/gcode_upload?s=secret';
    await expectLater(client.upload(file, 'test.gcode'), throwsFormatException);
    expect(requests, ['GET /info']);
  });
  test('Printer failure code and ambiguous HTTP 200 never report success', () async {
    code = 10011901;
    await expectLater(client.upload(file, 'test.gcode'), throwsFormatException);
    missingCode = true;
    await expectLater(client.upload(file, 'test.gcode'), throwsFormatException);
  });
  test('HTTP errors never report success', () async {
    httpError = 500;
    await expectLater(client.upload(file, 'test.gcode'), throwsFormatException);
  });
  test('Info redirect is not followed and does not upload', () async {
    redirect = true;
    await expectLater(client.upload(file, 'test.gcode'), throwsFormatException);
    expect(requests, ['GET /info']);
  });
  test('Cancelling a pending connection prevents upload', () async {
    hold = true;
    final pending = expectLater(client.upload(file, 'test.gcode'), throwsFormatException);
    await requestSeen!.future;
    client.cancel();
    await pending;
    expect(requests, ['GET /info']);
  });
  test('Invalid filenames and empty files fail before connecting', () async {
    await expectLater(client.upload(file, '../test.gcode'), throwsFormatException);
    await file.writeAsBytes([]);
    await expectLater(client.upload(file, 'test.gcode'), throwsFormatException);
    expect(requests, isEmpty);
  });
}
