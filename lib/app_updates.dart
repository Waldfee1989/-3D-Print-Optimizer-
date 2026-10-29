import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const releaseApi = 'https://api.github.com/repos/Waldfee1989/-3D-Print-Optimizer-/releases/latest';
const maximumApkBytes = 200 * 1024 * 1024;

class ReleaseUpdate {
  const ReleaseUpdate(this.build, this.url, this.size, this.digest);
  final int build, size;
  final Uri url;
  final String digest;

  static ReleaseUpdate? fromJson(Map<String, dynamic> data, int installedBuild) {
    if (data['draft'] == true || data['prerelease'] == true) return null;
    final match = RegExp(r'^build-(\d+)$').firstMatch('${data['tag_name']}');
    final build = match == null ? 0 : int.tryParse(match.group(1)!) ?? 0;
    if (build <= installedBuild) return null;
    final assets = data['assets'];
    if (assets is! List) return null;
    for (final asset in assets.whereType<Map>()) {
      if (asset['name'] != 'app-release.apk') continue;
      final expected = 'https://github.com/Waldfee1989/-3D-Print-Optimizer-/releases/download/build-$build/app-release.apk';
      final digest = '${asset['digest']}';
      final size = asset['size'];
      if (asset['browser_download_url'] != expected ||
          !RegExp(r'^sha256:[0-9a-fA-F]{64}$').hasMatch(digest) ||
          size is! int || size <= 0 || size > maximumApkBytes) {
        throw const FormatException('Updatedatei konnte nicht bestätigt werden.');
      }
      return ReleaseUpdate(build, Uri.parse(expected), size, digest.substring(7).toLowerCase());
    }
    throw const FormatException('Updatedatei fehlt.');
  }
}

class UpdateCancelled implements Exception {}

class UpdateDownloader {
  HttpClient? _client;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }

  static bool trustedDownload(Uri uri) => uri.scheme == 'https' &&
      uri.port == 443 && uri.userInfo.isEmpty && {
        'github.com', 'release-assets.githubusercontent.com',
        'objects.githubusercontent.com', 'github-releases.githubusercontent.com',
      }.contains(uri.host);

  Future<File> download(ReleaseUpdate update, Directory directory,
      void Function(double) progress) async {
    final client = _client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      var url = update.url;
      for (var redirects = 0; redirects <= 5; redirects++) {
        if (_cancelled) throw UpdateCancelled();
        if (!trustedDownload(url)) throw const FormatException('Ungültige Downloadadresse.');
        final request = await client.getUrl(url).timeout(const Duration(seconds: 15));
        request.followRedirects = false;
        request.headers.set(HttpHeaders.userAgentHeader, '3D-Print-Optimizer');
        final response = await request.close().timeout(const Duration(seconds: 20));
        if ({301, 302, 303, 307, 308}.contains(response.statusCode)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          await response.timeout(const Duration(seconds: 30)).drain<void>();
          if (location == null) throw const FormatException('Downloadadresse fehlt.');
          url = url.resolve(location);
          continue;
        }
        if (response.statusCode != HttpStatus.ok ||
            (response.contentLength >= 0 && response.contentLength != update.size)) {
          throw const FormatException('Update konnte nicht vollständig geladen werden.');
        }
        return await save(update, response.timeout(const Duration(seconds: 30)), directory, progress);
      }
      throw const FormatException('Zu viele Downloadweiterleitungen.');
    } finally {
      client.close(force: true);
      _client = null;
    }
  }

  // Separate streaming persistence permits regression tests without an HTTP server.
  Future<File> save(ReleaseUpdate update, Stream<List<int>> source,
      Directory directory, void Function(double) progress) async {
    await directory.create(recursive: true);
    final target = File('${directory.path}/update-${update.build}.apk');
    final partial = File('${target.path}.part');
    RandomAccessFile? output;
    try {
      output = await partial.open(mode: FileMode.write);
      var received = 0;
      await for (final chunk in source) {
        if (_cancelled) throw UpdateCancelled();
        received += chunk.length;
        if (received > update.size || received > maximumApkBytes) {
          throw const FormatException('Update-Dateigröße stimmt nicht überein.');
        }
        await output.writeFrom(chunk);
        progress(received / update.size);
      }
      await output.close();
      output = null;
      if (_cancelled) throw UpdateCancelled();
      if (received != update.size) throw const FormatException('Download ist unvollständig.');
      final digest = await sha256.bind(partial.openRead()).first;
      if (_cancelled) throw UpdateCancelled();
      if (digest.toString() != update.digest) {
        throw const FormatException('Prüfsumme stimmt nicht überein. Bitte erneut versuchen.');
      }
      return await partial.rename(target.path);
    } catch (_) {
      if (output != null) await output.close();
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
  }
}

Future<ReleaseUpdate?> findAppUpdate(int installedBuild) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
  try {
    final request = await client.getUrl(Uri.parse(releaseApi)).timeout(const Duration(seconds: 15));
    request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    request.headers.set(HttpHeaders.userAgentHeader, '3D-Print-Optimizer');
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode != HttpStatus.ok) throw const HttpException('Updates derzeit nicht erreichbar.');
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 15))) {
      bytes.addAll(chunk);
      if (bytes.length > 1024 * 1024) throw const FormatException('Ungültige Updateantwort.');
    }
    final data = jsonDecode(utf8.decode(bytes));
    if (data is! Map<String, dynamic>) throw const FormatException('Ungültige Updateantwort.');
    return ReleaseUpdate.fromJson(data, installedBuild);
  } finally {
    client.close(force: true);
  }
}

class UpdateInstaller {
  static const channel = MethodChannel('print_optimizer/app_updates');
  Future<Directory> directory() async {
    final path = await channel.invokeMethod<String>('updateDirectory');
    if (path == null) throw const FileSystemException('Updatespeicher nicht verfügbar.');
    return Directory(path);
  }
  Future<String?> install(File file, String digest) => channel.invokeMethod<String>(
      'installApk', {'path': file.path, 'sha256': digest});
  Future<void> permissionSettings() => channel.invokeMethod<void>('openInstallPermissionSettings');
  Future<void> cancel() async {
    try { await channel.invokeMethod<void>('cancelInstall'); } catch (_) { /* Activity may be gone. */ }
  }
}

class AppUpdateDialog extends StatefulWidget {
  const AppUpdateDialog({super.key, required this.update, this.installer, this.downloader});
  final ReleaseUpdate update;
  final UpdateInstaller? installer;
  final UpdateDownloader? downloader;
  @override State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> with WidgetsBindingObserver {
  late final UpdateDownloader downloader = widget.downloader ?? UpdateDownloader();
  late final UpdateInstaller installer = widget.installer ?? UpdateInstaller();
  File? downloaded;
  double progress = 0;
  bool busy = true, permissionNeeded = false, awaitingPermission = false, closing = false;
  String message = 'Update wird heruntergeladen …';

  @override void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    start();
  }
  @override void dispose() {
    downloader.cancel();
    installer.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && awaitingPermission && !closing) {
      awaitingPermission = false;
      openInstaller();
    }
  }

  Future<void> start() async {
    try {
      final directory = await installer.directory();
      if (!mounted || closing) return;
      // Keep only this release's APK; interrupted downloads are never installed.
      await for (final entity in directory.list()) {
        if (closing) return;
        if (entity is File && RegExp(r'^update-\d+\.apk(?:\.part)?$')
            .hasMatch(entity.uri.pathSegments.last)) {
          await entity.delete();
        }
      }
      downloaded = await downloader.download(widget.update, directory, (value) {
        if (mounted && !closing) setState(() => progress = value);
      });
      if (!mounted || closing) return;
      await openInstaller();
    } catch (_) {
      if (mounted && !closing) setState(() {
        busy = false;
        message = 'Das Update konnte nicht geladen oder geprüft werden. '
            'Bitte später über „Updates prüfen“ erneut versuchen.';
      });
    }
  }

  Future<void> openInstaller() async {
    final file = downloaded;
    if (file == null || !mounted || closing) return;
    setState(() { busy = true; permissionNeeded = false; message = 'Update wird geprüft …'; });
    try {
      final result = await installer.install(file, widget.update.digest);
      if (!mounted || closing) return;
      if (result == 'permissionRequired') {
        setState(() {
          busy = false;
          permissionNeeded = true;
          message = 'Android benötigt einmalig deine Erlaubnis, damit '
              '3D Print Optimizer Updates installieren darf. '
              'Aktiviere „Dieser Quelle vertrauen“ bzw. „Aus dieser Quelle zulassen“ '
              'und kehre danach zur App zurück.';
        });
      } else if (result == 'installerOpened') {
        Navigator.pop(context);
      } else {
        throw const FormatException('Installationsdialog nicht geöffnet.');
      }
    } catch (_) {
      if (mounted && !closing) setState(() {
        busy = false;
        message = 'Die Installation konnte nicht geöffnet werden. '
            'Bitte erneut versuchen. Die bisherige App bleibt erhalten.';
      });
    }
  }

  Future<void> allowInstallation() async {
    try {
      awaitingPermission = true;
      await installer.permissionSettings();
    } catch (_) {
      awaitingPermission = false;
      if (mounted) setState(() => message = 'Die Android-Einstellung konnte nicht geöffnet werden. '
          'Du findest sie unter Einstellungen → Apps → Spezieller App-Zugriff → Unbekannte Apps installieren.');
    }
  }

  @override Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text('Update auf Build ${widget.update.build}'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message),
          if (busy) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: downloaded == null ? progress : null),
            if (downloaded == null) Text('${(progress * 100).round()} %'),
          ],
        ]),
      actions: [
        TextButton(onPressed: () {
          closing = true;
          awaitingPermission = false;
          downloader.cancel();
          installer.cancel();
          Navigator.pop(context);
        },
          child: Text(busy ? 'Abbrechen' : 'Schließen')),
        if (!busy && permissionNeeded)
          FilledButton(onPressed: allowInstallation, child: const Text('Installation erlauben')),
        if (!busy && !permissionNeeded && downloaded != null)
          FilledButton(onPressed: openInstaller, child: const Text('Erneut versuchen')),
      ],
    ),
  );
}
