import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';

// Protocol constants of the existing public web client, not account credentials.
// Source: anycubic-cloud-api 0.4.36 (const/const.py, models/auth.py).
const _webApplicationId = 'f9b3528877c94d5c9c5af32245db46ef';
const _webSigningKey = '0cf75926606049a3937f56b0373b99fb';
const cloudApiHost = 'cloud-universe.anycubic.com';
const cloudApiPath = '/p/p/workbench/api';

bool cloudLoginNavigation(Uri uri) => uri.scheme == 'https' && uri.port == 443 && uri.userInfo.isEmpty &&
  (uri.host == 'anycubic.com' || uri.host.endsWith('.anycubic.com') ||
   uri.host == 'makeronline.com' || uri.host.endsWith('.makeronline.com') ||
   uri.host == 'accounts.google.com' || uri.host == 'appleid.apple.com');

String cloudSessionToken(Object value) {
  var text = value is String ? value.trim() : '';
  if (text.startsWith('"')) {
    try { final decoded = jsonDecode(text); text = decoded is String ? decoded : ''; } catch (_) { text = ''; }
  }
  if (text.length < 16 || text.length > 16384 || text.contains(RegExp(r'\s')) || text == 'null') {
    throw const FormatException('Noch keine angemeldete Anycubic-Sitzung gefunden. Bitte auf der offiziellen Seite anmelden.');
  }
  return text;
}

bool cloudStorageDestination(Uri uri) {
  if (uri.scheme != 'https' || uri.port != 443 || uri.userInfo.isNotEmpty || uri.hasFragment) return false;
  return RegExp(r'^[a-z0-9][a-z0-9.-]*\.s3(?:[.-][a-z0-9-]+)?\.amazonaws\.com$').hasMatch(uri.host);
}

int _integer(Object? value) => value is int ? value : int.tryParse('$value') ?? -1;

class CloudPrinter {
  CloudPrinter(Map<String, dynamic> data) : id = _integer(data['id']),
    name = data['name'] is String ? data['name'] as String : 'Kobra S1',
    model = '${data['model']}', online = _integer(data['device_status']) == 1,
    idle = _integer(data['is_printing']) == 2, details = Map.unmodifiable(data) {
    if (id <= 0 || name.length > 200 || !['kobra s1', 'kobra s1 combo'].contains(model.toLowerCase().replaceFirst('anycubic ', '').trim())) {
      throw const FormatException('Drucker ist kein unterstützter Kobra S1.');
    }
  }
  final int id;
  final String name, model;
  final bool online, idle;
  final Map<String, dynamic> details;
}

class CloudFile {
  CloudFile._(this.id, this.name, this.bytes, this.owner);
  CloudFile.test(this.id, this.name, this.bytes, this.owner);
  final int id, bytes;
  final String name;
  final AnycubicCloudClient owner;
  bool startAttempted = false;
}

class CloudSlot {
  const CloudSlot(this.index, this.material, this.color);
  final int index;
  final String material;
  final List<int> color;
}

List<CloudSlot> cloudSlots(CloudPrinter printer) {
  final value = printer.details['multi_color_box'];
  final boxes = value is List ? value : value is Map ? [value] : [];
  final output = <CloudSlot>[];
  // First implementation supports the user's single four-slot ACE Pro only.
  if (boxes.length != 1 || boxes.first is! Map || (boxes.first as Map)['slots'] is! List) return output;
  for (final raw in (boxes.first as Map)['slots'] as List) {
    if (raw is! Map || ![0, 1].contains(_integer(raw['edit_status']))) continue;
    final index = _integer(raw['index']), material = raw['type'], color = raw['color'];
    if (index < 0 || index > 3 || material is! String || color is! List || color.length < 3 ||
        color.take(3).any((v) => v is! int || v < 0 || v > 255)) continue;
    output.add(CloudSlot(index, material, List<int>.from(color.take(3))));
  }
  return output;
}

class AnycubicCloudClient {
  AnycubicCloudClient(String token, {String? userAgent}) : _token = cloudSessionToken(token), _userAgent = userAgent,
    _base = Uri.https(cloudApiHost), _test = false;
  AnycubicCloudClient.test(String token, int port) : _token = cloudSessionToken(token),
    _base = Uri(scheme: 'http', host: '127.0.0.1', port: port), _test = true, _userAgent = null;
  String? _token;
  final String? _userAgent;
  final Uri _base;
  final bool _test;
  final _clients = <HttpClient>{};
  final _ownedPrinters = <int>{};
  bool _cancelled = false, _busy = false;
  void cancel() { _cancelled = true; for (final client in _clients.toList()) { client.close(force: true); } }
  void logout() { cancel(); _token = null; _ownedPrinters.clear(); }
  void _check() { if (_cancelled) throw const FormatException('Cloud-Anfrage abgebrochen. Vor erneutem Senden den Status in der Anycubic-App prüfen.'); }

  Future<T> _operation<T>(Future<T> Function() action) async {
    if (_busy) throw const FormatException('Eine Cloud-Anfrage läuft bereits.');
    if (_token == null) throw const FormatException('Bitte erneut bei Anycubic anmelden.');
    _busy = true; _cancelled = false;
    try { return await action().timeout(const Duration(minutes: 8));
    } on FormatException { rethrow;
    } catch (_) {
      _check();
      throw const FormatException('Die Anycubic-Cloud ist nicht erreichbar oder die Anfrage wurde unterbrochen. Vor einer Wiederholung Cloud-Dateien und Druckerstatus prüfen.');
    } finally { for (final client in _clients.toList()) { client.close(force: true); } _clients.clear(); _busy = false; }
  }

  Map<String, String> _headers() {
    final random = Random.secure();
    final digits = List.generate(16, (_) => random.nextInt(256));
    digits[6] = (digits[6] & 15) | 64; digits[8] = (digits[8] & 63) | 128;
    final hex = digits.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
    final nonce = '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final signature = md5.convert(utf8.encode('$_webApplicationId${timestamp}1.0.0$_webSigningKey$nonce$_webApplicationId'));
    return {'Xx-Device-Type': 'web', 'Xx-Is-Cn': '1', 'Xx-Nonce': nonce,
      'Xx-Timestamp': timestamp, 'Xx-Version': '1.0.0', 'Xx-Signature': '$signature',
      'XX-Token': _token!, 'XX-LANGUAGE': 'US', 'Origin': 'https://uc.makeronline.com'};
  }

  Future<List<int>> _body(HttpClientResponse response, {int limit = 2 * 1024 * 1024}) async {
    final data = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 30))) {
      _check();
      if (data.length + chunk.length > limit) throw const FormatException('Die Cloud-Antwort ist zu groß.');
      data.addAll(chunk);
    }
    return data;
  }

  Future<dynamic> _api(String path, {Map<String, Object?>? data, Map<String, String>? query}) async {
    _check();
    if (_token == null) throw const FormatException('Bitte erneut bei Anycubic anmelden.');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15); _clients.add(client);
    try {
      final uri = _base.replace(path: '$cloudApiPath$path', queryParameters: query);
      final request = await client.openUrl(data == null ? 'GET' : 'POST', uri).timeout(const Duration(seconds: 20));
      request.followRedirects = false;
      _headers().forEach(request.headers.set);
      if (_userAgent != null && _userAgent!.length < 1024 && !_userAgent!.contains(RegExp(r'[\r\n]'))) request.headers.set(HttpHeaders.userAgentHeader, _userAgent!);
      request.headers.contentType = ContentType.json;
      if (data != null) request.add(utf8.encode(jsonEncode(data)));
      final response = await request.close().timeout(const Duration(seconds: 45));
      final bytes = await _body(response);
      if (response.statusCode == 401 || response.statusCode == 403) {
        _token = null; throw const FormatException('Die Cloud-Anmeldung ist abgelaufen oder wurde abgelehnt. Bitte erneut anmelden.');
      }
      if (response.statusCode != 200) throw FormatException('Anycubic-Cloud antwortet mit HTTP ${response.statusCode}.');
      dynamic value;
      try { value = jsonDecode(utf8.decode(bytes)); } catch (_) { throw const FormatException('Keine gültige Cloud-Bestätigung erhalten.'); }
      final code = value is Map ? _integer(value['code']) : -1;
      // The deployed official web client uses code 1 for REST success.
      // 0/200 remain accepted for compatible API versions, not arbitrary codes.
      if (code == 10001) {
        _token = null;
        throw const FormatException('Die Cloud-Anmeldung ist abgelaufen (Cloud-Code 10001). Bitte bei Anycubic erneut anmelden.');
      }
      if (value is! Map || ![0, 1, 200].contains(code) || !value.containsKey('data') || value['data'] == null) {
        final action = path.endsWith('/getPrinters') ? 'Die Druckerliste' : path.endsWith('/printer/info') ? 'Der Druckerstatus' : 'Die Cloud-Anfrage';
        final detail = code >= 0 && code <= 999999999 ? ' (Cloud-Code $code)' : '';
        // Never show server messages: they can contain account/session data.
        throw FormatException('$action konnte nicht bestätigt werden$detail. Bitte die Anmeldung und Cloud-Verbindung prüfen.');
      }
      return value['data'];
    } finally { client.close(force: true); _clients.remove(client); }
  }

  Future<List<CloudPrinter>> listPrinters() => _operation(() async {
    final data = await _api('/work/printer/getPrinters');
    if (data is! List || data.length > 100) throw const FormatException('Unerwartete Druckerliste von Anycubic.');
    final result = <CloudPrinter>[];
    for (final raw in data) {
      if (raw is! Map) continue;
      try { result.add(CloudPrinter(Map<String, dynamic>.from(raw))); } on FormatException { continue; }
    }
    _ownedPrinters..clear()..addAll(result.map((p) => p.id));
    return result;
  });

  Future<CloudPrinter> _printer(int id) async {
    if (!_ownedPrinters.contains(id)) throw const FormatException('Bitte einen Drucker aus deinem verbundenen Konto wählen.');
    final data = await _api('/v2/printer/info', query: {'id': '$id'});
    if (data is! Map) throw const FormatException('Druckerstatus konnte nicht gelesen werden.');
    final result = CloudPrinter(Map<String, dynamic>.from(data));
    if (result.id != id) throw const FormatException('Die Cloud hat einen anderen Drucker gemeldet.');
    return result;
  }
  Future<CloudPrinter> refreshPrinter(int id) => _operation(() => _printer(id));

  Future<CloudFile> upload(File file, String filename, {void Function(int, int)? progress}) => _operation(() async {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,100}\.gcode$').hasMatch(filename)) throw const FormatException('Ungültiger Druckdateiname.');
    final total = await file.length();
    if (total < 16 || total > 128 * 1024 * 1024) throw const FormatException('Die Cloud-Druckdatei muss zwischen 16 Byte und 128 MB groß sein.');
    final lock = await _api('/v2/cloud_storage/lockStorageSpace', data: {'size': total, 'name': filename, 'is_temp_file': 0});
    if (lock is! Map || _integer(lock['id']) <= 0 || lock['preSignUrl'] is! String) throw const FormatException('Die Cloud hat keinen Upload reserviert.');
    final lockId = _integer(lock['id']);
    var claimed = false, claimAttempted = false;
    try {
      final destination = Uri.tryParse(lock['preSignUrl'] as String);
      if (destination == null || (!cloudStorageDestination(destination) && !(_test && destination.scheme == 'http' && destination.host == '127.0.0.1' && destination.port == _base.port && destination.path == '/storage'))) {
        throw const FormatException('Unerwartetes Cloud-Speicherziel. Die Datei wurde nicht hochgeladen.');
      }
      _check();
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 15); _clients.add(client);
      try {
        final request = await client.putUrl(destination).timeout(const Duration(seconds: 20));
        request.followRedirects = false; request.contentLength = total;
        request.headers.contentType = ContentType.binary;
        // No Anycubic session or signature headers are sent to object storage.
        var sent = 0; progress?.call(0, total);
        await request.addStream(file.openRead().map((chunk) { _check(); sent += chunk.length; progress?.call(sent, total); return chunk; })).timeout(const Duration(minutes: 6));
        final response = await request.close().timeout(const Duration(seconds: 45));
        await _body(response, limit: 65536);
        if (![200, 201, 204].contains(response.statusCode)) throw const FormatException('Der Cloud-Dateiupload wurde abgelehnt.');
      } finally { client.close(force: true); _clients.remove(client); }
      claimAttempted = true;
      final data = await _api('/v2/profile/newUploadFile', data: {'user_lock_space_id': lockId});
      if (data is! Map || _integer(data['id']) <= 0) throw const FormatException('Die Cloud hat die Datei nicht registriert.');
      claimed = true;
      await _api('/v2/cloud_storage/unlockStorageSpace', data: {'id': lockId, 'is_delete_cos': 0});
      return CloudFile._(_integer(data['id']), filename, total, this);
    } catch (_) {
      // Cleanup only an unclaimed reservation. Never delete a registered file,
      // and never issue a print retry after an uncertain response.
      if (!claimed && !claimAttempted && !_cancelled && _token != null) {
        try { await _api('/v2/cloud_storage/unlockStorageSpace', data: {'id': lockId, 'is_delete_cos': 1}); } catch (_) {}
      }
      rethrow;
    }
  });

  Future<String> startPrint(CloudFile file, CloudPrinter printer, String material, int? slotIndex, {required bool confirmed}) => _operation(() async {
    if (!confirmed || !identical(file.owner, this) || file.startAttempted) throw const FormatException('Ein Druckstart braucht eine neue ausdrückliche Bestätigung. Bereits versendete Aufträge nicht erneut senden.');
    if (!['PLA', 'PETG', 'ASA', 'ABS', 'TPU'].contains(material.toUpperCase())) throw const FormatException('Dieses Material ist für den Cloud-Druck noch nicht unterstützt.');
    final fresh = await _printer(printer.id);
    if (!fresh.online || !fresh.idle) throw const FormatException('Drucker ist offline, beschäftigt oder sein Bereitschaftsstatus ist unbekannt.');
    Map<String, dynamic>? ams;
    final boxes = fresh.details['multi_color_box'];
    if (slotIndex != null) {
      final slots = cloudSlots(fresh).where((s) => s.index == slotIndex && s.material.toUpperCase() == material.toUpperCase()).toList();
      if (slots.length != 1) throw const FormatException('Der gewählte ACE-Platz ist leer, nicht eindeutig oder enthält ein anderes Material.');
      final slot = slots.single;
      ams = {'use_ams': true, 'ams_box_mapping': [{'ams_index': slot.index, 'paint_index': 0,
        'ams_color': slot.color, 'paint_color': slot.color, 'material_type': slot.material,
        'filament_used': 0}]}; // Unknown grams; never invent a consumption value.
    } else if (!fresh.details.containsKey('multi_color_box') || boxes is Map || boxes is List && boxes.isNotEmpty) {
      throw const FormatException('Bei angeschlossenem ACE bitte einen bestätigten Filamentplatz wählen.');
    }
    file.startAttempted = true; // Never retry a physical command automatically.
    final reply = await _api('/work/operation/sendOrder', data: {
      'printer_id': fresh.id, 'order_id': 1, 'project_id': 0, 'ams_info': ams, 'settings': null,
      'data': {'file_id': file.id, 'filetype': 0, 'file_key': '', 'file_name': '',
        'task_settings': {'ai_detect': 0, 'camera_timelapse': 0}, 'hollow_param': null,
        'is_delete_file': 0, 'matrix': '', 'project_type': 1, 'punching_param': null,
        'slice_param': null, 'slice_size': null, 'template_id': 0},
    });
    if (reply is! Map || reply['msgid'] is! String || (reply['msgid'] as String).isEmpty) {
      throw const FormatException('Keine eindeutige Auftragsbestätigung. Bitte den Druckerstatus in der Anycubic-App prüfen und den Auftrag nicht erneut senden.');
    }
    return reply['msgid'] as String;
  });
}
