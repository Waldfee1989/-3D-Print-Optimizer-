import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Stock Anycubic LAN upload only. No MQTT, print-start, heating or motion calls.
class KobraLanInfo {
  const KobraLanInfo(this.ip, this.name, this.upload);
  final String ip, name;
  final Uri upload;
}

String kobraLanIp(String input) {
  final raw = input.trim();
  final ip = InternetAddress.tryParse(raw);
  if (ip == null || ip.type != InternetAddressType.IPv4 || ip.address != raw) {
    throw const FormatException('Die lokale IPv4-Adresse des Druckers eingeben, zum Beispiel 192.168.1.50.');
  }
  final b = ip.rawAddress;
  final local = b[0] == 10 || b[0] == 172 && b[1] >= 16 && b[1] <= 31 || b[0] == 192 && b[1] == 168;
  if (!local || b[3] == 0 || b[3] == 255) {
    throw const FormatException('Eine lokale Drucker-IP aus deinem WLAN verwenden.');
  }
  return raw;
}

Uri kobraUploadUri(String ip, Object? value, {int port = 18910}) {
  if (value is! String || value.length > 4096) {
    throw const FormatException('Der Drucker stellt keine direkte Upload-Adresse bereit. Die LAN-Schnittstelle dieser Firmware muss noch angepasst werden.');
  }
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme != 'http' || uri.host != ip || uri.port != port ||
      uri.userInfo.isNotEmpty || uri.hasFragment || uri.path != '/gcode_upload') {
    throw const FormatException('Der Drucker meldet eine unerwartete Upload-Adresse. Es wurde nichts gesendet.');
  }
  return uri;
}

String kobraFilename(String name) {
  var safe = name.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  if (safe.length > 60) safe = safe.substring(0, 60);
  if (safe.isEmpty) safe = 'Druckmodell';
  return '${safe}_${DateTime.now().millisecondsSinceEpoch}.gcode';
}

class KobraLanClient {
  KobraLanClient(String ip) : ip = kobraLanIp(ip), port = 18910;
  // The production constructor accepts only literal private WLAN addresses.
  KobraLanClient.test(this.ip, this.port) {
    if (ip != '127.0.0.1') throw ArgumentError('Test transport must use loopback.');
  }
  final String ip;
  final int port;
  HttpClient? _active;
  bool _cancelled = false;
  bool _busy = false;
  void cancel() { _cancelled = true; _active?.close(force: true); }
  void _check() { if (_cancelled) throw const FormatException('Übertragung abgebrochen. Der Drucker kann bereits einen Teil der Datei erhalten haben.'); }

  Future<T> _session<T>(Future<T> Function(HttpClient) action) async {
    if (_busy) throw const FormatException('Eine Druckeranfrage läuft bereits.');
    _busy = true; _cancelled = false;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8)..findProxy = (_) => 'DIRECT';
    _active = client;
    try {
      return await action(client).timeout(const Duration(minutes: 8));
    } on FormatException { rethrow;
    } on TimeoutException {
      throw const FormatException('Zeitüberschreitung. Prüfe LAN-Modus, Drucker-IP und WLAN. Vor erneutem Senden die Dateiliste am Drucker prüfen.');
    } catch (_) {
      _check();
      // Never include URLs, printer tokens or raw printer errors in diagnostics.
      throw const FormatException('Verbindung unterbrochen. Prüfe LAN-Modus, Drucker-IP und dass beide Geräte im selben WLAN sind.');
    } finally { client.close(force: true); _active = null; _busy = false; }
  }

  Future<Map<String, dynamic>> _json(HttpClientResponse response) async {
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 20))) {
      _check();
      if (bytes.length + chunk.length > 256 * 1024) throw const FormatException('Unerwartet große Antwort des Druckers.');
      bytes.addAll(chunk);
    }
    if (response.statusCode != 200) throw FormatException('Der Drucker hat die Anfrage abgelehnt (HTTP ${response.statusCode}).');
    final Object? value;
    try { value = jsonDecode(utf8.decode(bytes)); } catch (_) { throw const FormatException('Keine gültige Bestätigung des Druckers erhalten.'); }
    if (value is! Map<String, dynamic>) throw const FormatException('Unerwartete Antwort des Druckers.');
    if (value.containsKey('code') && value['code'] != 0 && value['code'] != 200) {
      final code = value['code'];
      throw FormatException('Der Drucker hat die Datei oder Anfrage abgelehnt${code is num ? ' (Code $code)' : ''}. Das Dateiformat muss gegebenenfalls angepasst werden.');
    }
    return value;
  }

  Future<KobraLanInfo> _inspect(HttpClient client) async {
    _check();
    final request = await client.getUrl(Uri(scheme: 'http', host: ip, port: port, path: '/info')).timeout(const Duration(seconds: 10));
    request.followRedirects = false;
    final value = await _json(await request.close().timeout(const Duration(seconds: 15)));
    final data = value['data'] is Map<String, dynamic> ? value['data'] as Map<String, dynamic> : value;
    if (data['modelId']?.toString() != '20025') {
      throw const FormatException('An dieser IP wurde kein Kobra S1 erkannt. Bitte die Drucker-IP prüfen.');
    }
    final urls = data['urls'];
    final upload = kobraUploadUri(ip, data['fileUploadurl'] ?? (urls is Map ? urls['fileUploadurl'] : null), port: port);
    return KobraLanInfo(ip, 'Anycubic Kobra S1', upload);
  }

  Future<KobraLanInfo> inspect() => _session(_inspect);

  Future<String> upload(File file, String filename, {void Function(int sent, int total)? progress}) => _session((client) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,100}\.gcode$').hasMatch(filename)) throw const FormatException('Ungültiger Druckdateiname.');
    final total = await file.length();
    if (total < 16 || total > 512 * 1024 * 1024) throw const FormatException('Die Druckdatei muss zwischen 16 Byte und 512 MB groß sein.');
    // Refresh the short-lived upload URL for every transfer; never store tokens.
    final info = await _inspect(client);
    _check();
    final random = Random.secure();
    final boundary = 'Optimizer${List.generate(24, (_) => random.nextInt(16).toRadixString(16)).join()}';
    final prefix = utf8.encode('--$boundary\r\nContent-Disposition: form-data; name="filename"\r\n\r\n$filename\r\n'
        '--$boundary\r\nContent-Disposition: form-data; name="gcode"; filename="$filename"\r\nContent-Type: application/octet-stream\r\n\r\n');
    final suffix = utf8.encode('\r\n--$boundary--\r\n');
    final request = await client.postUrl(info.upload).timeout(const Duration(seconds: 10));
    request.followRedirects = false;
    request.headers.set(HttpHeaders.contentTypeHeader, 'multipart/form-data; boundary=$boundary');
    request.headers.set('X-File-Length', '$total');
    request.headers.set('X-BBL-Client-Name', 'AnycubicSlicerNext');
    request.headers.set('X-BBL-Client-Type', 'slicer');
    request.contentLength = prefix.length + total + suffix.length;
    request.add(prefix);
    var sent = 0;
    progress?.call(0, total);
    await request.addStream(file.openRead().map((chunk) {
      _check(); sent += chunk.length; progress?.call(sent, total); return chunk;
    })).timeout(const Duration(minutes: 6));
    _check(); request.add(suffix);
    final reply = await _json(await request.close().timeout(const Duration(seconds: 60)));
    _check();
    if (!reply.containsKey('code')) throw const FormatException('Die Übertragung wurde nicht eindeutig bestätigt. Vor erneutem Senden die Dateiliste am Drucker prüfen.');
    return filename;
  });
}
