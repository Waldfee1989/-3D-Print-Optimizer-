import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:print_optimizer/anycubic_cloud.dart';

const token = 'synthetic-test-session-not-a-real-account';
Map<String, dynamic> printerData({int online = 1, int printing = 2}) => {
  'id': 41, 'name': 'Test-Kobra', 'model': 'Anycubic Kobra S1', 'device_status': online, 'is_printing': printing,
  'multi_color_box': [{'id': 0, 'slots': [{'index': 0, 'type': 'PLA', 'color': [10, 20, 30], 'edit_status': 0, 'status': 4},
    {'index': 1, 'type': 'PLA', 'color': [10, 20, 30], 'edit_status': 2, 'status': 4}]}],
};

void main() {
  test('Login origins, token values and signed storage destinations are constrained', () {
    expect(cloudSessionToken(jsonEncode(token)), token);
    for (final value in ['', 'null', 'short', '$token\nextra']) { expect(() => cloudSessionToken(value), throwsFormatException); }
    expect(cloudLoginNavigation(Uri.parse('https://uc.makeronline.com/login')), true);
    expect(cloudLoginNavigation(Uri.parse('https://cloud-universe.anycubic.com/file')), true);
    for (final u in ['http://cloud-universe.anycubic.com', 'https://anycubic.com.evil.test', 'https://user@cloud-universe.anycubic.com', 'javascript:alert(1)']) {
      expect(cloudLoginNavigation(Uri.parse(u)), false);
    }
    expect(cloudStorageDestination(Uri.parse('https://workbentch.s3.us-east-2.amazonaws.com/file?signature=test')), true);
    for (final u in ['http://bucket.s3.us-east-2.amazonaws.com/file', 'https://evil.test/file', 'https://bucket.s3.us-east-2.amazonaws.com.evil.test/file', 'https://127.0.0.1/file']) {
      expect(cloudStorageDestination(Uri.parse(u)), false);
    }
    expect(cloudSlots(CloudPrinter(printerData())).map((s) => s.index), [0]);
  });

  late HttpServer server;
  late Directory directory;
  late File file;
  late AnycubicCloudClient client;
  final requests = <String>[], bodies = <String, dynamic>{};
  final bytes = utf8.encode('; synthetic test only\nG90\nG1 X10 Y20\n');
  var online = 1, printing = 2, storageStatus = 200;
  Object? apiCode = 1;
  bool hostileStorage = false, failClaim = false, failOrder = false, authExpired = false;
  var expectedUploadBytes = 0;
  List<int>? received;
  List<String>? storageHeaders;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('optimizer-cloud-test-');
    file = await File('${directory.path}/test.gcode').writeAsBytes(bytes);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = AnycubicCloudClient.test(token, server.port);
    requests.clear(); bodies.clear(); received = null; storageHeaders = null;
    online = 1; printing = 2; storageStatus = 200; apiCode = 1;
    expectedUploadBytes = bytes.length;
    hostileStorage = false; failClaim = false; failOrder = false; authExpired = false;
    server.listen((request) async {
      try {
        final path = request.uri.path;
        requests.add('${request.method} $path');
        if (path == '/storage') {
          storageHeaders = [];
          request.headers.forEach((name, values) { storageHeaders!.add(name); });
          received = await request.fold<List<int>>([], (all, chunk) => all..addAll(chunk));
          request.response.statusCode = storageStatus;
          await request.response.close(); return;
        }
        expect(request.headers.value('XX-Token'), token);
        expect(request.headers.value('Xx-Signature'), matches(RegExp(r'^[a-f0-9]{32}$')));
        expect(request.headers.value('Xx-Nonce'), matches(RegExp(r'^[a-f0-9-]{36}$')));
        request.response.headers.contentType = ContentType.json;
        if (authExpired) { request.response.statusCode = 401; request.response.write('{"secret":"DO_NOT_SHOW"}'); await request.response.close(); return; }
        dynamic body;
        if (request.method == 'POST') body = jsonDecode(await utf8.decoder.bind(request).join());
        bodies[path] = body;
        dynamic response;
        var code = apiCode;
        if (path.endsWith('/getPrinters')) { response = [printerData(online: online, printing: printing)];
        } else if (path.endsWith('/printer/info')) { expect(request.uri.queryParameters['id'], '41'); response = printerData(online: online, printing: printing);
        } else if (path.endsWith('/lockStorageSpace')) {
          expect(body['size'], expectedUploadBytes); expect(body['name'], 'test.gcode'); expect(body['is_temp_file'], 0);
          response = {'id': 101, 'preSignUrl': hostileStorage ? 'https://evil.test/steal' : 'http://127.0.0.1:${server.port}/storage?signature=synthetic'};
        } else if (path.endsWith('/newUploadFile')) { expect(body['user_lock_space_id'], 101); response = {'id': 202}; if (failClaim) code = 500;
        } else if (path.endsWith('/unlockStorageSpace')) { expect(body['id'], 101); response = '';
        } else if (path.endsWith('/sendOrder')) { response = {'msgid': 'synthetic-accepted-job'}; if (failOrder) code = 500;
        } else { throw StateError('Unexpected endpoint: $path'); }
        request.response.write(jsonEncode({'code': code, 'data': response, 'msg': 'DO_NOT_SHOW'}));
        await request.response.close();
      } on SocketException { } on HttpException { }
    });
  });
  tearDown(() async { client.logout(); await server.close(force: true); await directory.delete(recursive: true); });
  test('REST success codes include the official web code 1 and numeric strings', () async {
    for (final code in [1, '1', 0, 200]) {
      apiCode = code;
      expect((await client.listPrinters()).single.id, 41);
    }
    expect(requests.any((r) => r.contains('sendOrder')), false);
  });
  test('Rejected list reports only the stage and safe code, not secrets or an empty account', () async {
    apiCode = 500;
    try { await client.listPrinters(); fail('Should reject'); } on FormatException catch (e) {
      expect(e.message, contains('Druckerliste'));
      expect(e.message, contains('Cloud-Code 500'));
      expect(e.message, isNot(contains('DO_NOT_SHOW')));
      expect(e.message, isNot(contains('Dateiformat')));
    }
  });
  test('REST expired-session code blocks further requests, even with data present', () async {
    apiCode = 10001;
    await expectLater(client.listPrinters(), throwsFormatException);
    final count = requests.length;
    apiCode = 1;
    await expectLater(client.listPrinters(), throwsFormatException);
    expect(requests.length, count);
  });
  test('Cloud upload streams unchanged bytes, registers the file and sends no print order', () async {
    await client.listPrinters();
    final progress = <int>[];
    final uploaded = await client.upload(file, 'test.gcode', progress: (sent, total) { expect(total, bytes.length); progress.add(sent); });
    expect(uploaded.id, 202); expect(uploaded.startAttempted, false); expect(received, bytes);
    expect(storageHeaders, isNot(contains('xx-token'))); expect(storageHeaders, isNot(contains('xx-signature')));
    expect(progress.first, 0); expect(progress.last, bytes.length);
    expect(requests.where((r) => r.contains('sendOrder')), isEmpty);
    expect(bodies['$cloudApiPath/v2/cloud_storage/unlockStorageSpace']['is_delete_cos'], 0);
  });
  test('Print requires confirmation, fresh idle status and valid ACE material mapping; never retries', () async {
    final printer = (await client.listPrinters()).single;
    final uploaded = await client.upload(file, 'test.gcode');
    await expectLater(client.startPrint(uploaded, printer, 'PLA', 0, confirmed: false), throwsFormatException);
    await expectLater(client.startPrint(uploaded, printer, 'PLA', 1, confirmed: true), throwsFormatException);
    expect(requests.where((r) => r.contains('sendOrder')), isEmpty);
    expect(await client.startPrint(uploaded, printer, 'PLA', 0, confirmed: true), 'synthetic-accepted-job');
    final body = bodies['$cloudApiPath/work/operation/sendOrder'];
    expect(body['printer_id'], 41); expect(body['order_id'], 1); expect(body['data']['file_id'], 202);
    expect(body['ams_info']['ams_box_mapping'].single['ams_index'], 0);
    expect(body['ams_info']['ams_box_mapping'].single['ams_color'], [10, 20, 30]);
    await expectLater(client.startPrint(uploaded, printer, 'PLA', 0, confirmed: true), throwsFormatException);
    expect(requests.where((r) => r.contains('sendOrder')).length, 1);
  });
  test('Offline and busy printer are refused even when the previous list was idle', () async {
    final printer = (await client.listPrinters()).single, uploaded = await client.upload(file, 'test.gcode');
    online = 2;
    await expectLater(client.startPrint(uploaded, printer, 'PLA', 0, confirmed: true), throwsFormatException);
    online = 1; printing = 1;
    await expectLater(client.startPrint(uploaded, printer, 'PLA', 0, confirmed: true), throwsFormatException);
    expect(requests.where((r) => r.contains('sendOrder')), isEmpty);
  });
  test('A rejected or uncertain start remains single-attempt and never claims printing', () async {
    final printer = (await client.listPrinters()).single, uploaded = await client.upload(file, 'test.gcode');
    failOrder = true;
    await expectLater(client.startPrint(uploaded, printer, 'PLA', 0, confirmed: true), throwsFormatException);
    expect(uploaded.startAttempted, true);
    await expectLater(client.startPrint(uploaded, printer, 'PLA', 0, confirmed: true), throwsFormatException);
    expect(requests.where((r) => r.contains('sendOrder')).length, 1);
  });
  test('Foreign object storage never receives bytes; only the unclaimed reservation is cleaned up', () async {
    hostileStorage = true;
    await expectLater(client.upload(file, 'test.gcode'), throwsFormatException);
    expect(received, isNull); expect(requests.any((r) => r.contains('newUploadFile')), false);
    expect(bodies['$cloudApiPath/v2/cloud_storage/unlockStorageSpace']['is_delete_cos'], 1);
  });
  test('Files above 128 MiB reach cloud reservation; files above 500 MB are refused before network', () async {
    final handle = await file.open(mode: FileMode.write);
    await handle.truncate(129 * 1024 * 1024); await handle.close();
    expectedUploadBytes = await file.length(); hostileStorage = true;
    try { await client.upload(file, 'test.gcode'); fail('Should refuse untrusted destination'); } on FormatException catch (e) {
      expect(e.message, contains('Speicherziel'));
    }
    expect(requests.any((r) => r.contains('lockStorageSpace')), true);
    expect(received, isNull);
    requests.clear();
    final large = await file.open(mode: FileMode.write);
    await large.truncate(500000001); await large.close();
    await expectLater(client.upload(file, 'test.gcode'), throwsFormatException);
    expect(requests, isEmpty);
  });
  test('Failed PUT cannot be reported as a cloud file', () async {
    storageStatus = 500;
    await expectLater(client.upload(file, 'test.gcode'), throwsFormatException);
    expect(requests.any((r) => r.contains('newUploadFile')), false);
  });
  test('Uncertain claim does not delete possibly registered data', () async {
    failClaim = true;
    await expectLater(client.upload(file, 'test.gcode'), throwsFormatException);
    expect(requests.any((r) => r.contains('unlockStorageSpace')), false);
    expect(requests.any((r) => r.contains('sendOrder')), false);
  });
  test('Expired auth is redacted and blocks all further requests until sign-in', () async {
    authExpired = true;
    try { await client.listPrinters(); fail('Should reject expired auth'); } on FormatException catch (e) {
      expect(e.message, isNot(contains(token))); expect(e.message, isNot(contains('DO_NOT_SHOW')));
    }
    final count = requests.length;
    await expectLater(client.listPrinters(), throwsFormatException);
    expect(requests.length, count);
  });
}
