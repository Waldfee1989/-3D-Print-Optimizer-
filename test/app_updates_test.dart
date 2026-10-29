import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:print_optimizer/app_updates.dart';

final payload = <int>[80, 75, 3, 4, 10, 20];
final checksum = sha256.convert(payload).toString();
final url = Uri.parse('https://github.com/Waldfee1989/-3D-Print-Optimizer-/releases/download/build-40/app-release.apk');
ReleaseUpdate fixture({int? size, String? digest}) =>
    ReleaseUpdate(40, url, size ?? payload.length, digest ?? checksum);

Map<String, dynamic> release({int build = 40, String? download, String? digest, int? size}) => {
  'tag_name': 'build-$build', 'draft': false, 'prerelease': false,
  'assets': [{ 'name': 'app-release.apk', 'size': size ?? payload.length,
    'digest': digest ?? 'sha256:$checksum',
    'browser_download_url': download ?? url.toString(), }],
};

class FakeDownloader extends UpdateDownloader {
  FakeDownloader(this.file, {this.pending});
  final File file;
  final Completer<File>? pending;
  bool cancelled = false;
  @override void cancel() { cancelled = true; super.cancel(); }
  @override Future<File> download(ReleaseUpdate update, Directory directory,
      void Function(double) progress) async {
    if (pending != null) return await pending!.future;
    return file;
  }
}

class FakeInstaller extends UpdateInstaller {
  FakeInstaller(this.root);
  final Directory root;
  int installs = 0, settings = 0, cancellations = 0;
  bool permission = true;
  @override Future<Directory> directory() async => root;
  @override Future<String?> install(File file, String digest) async {
    installs++;
    return permission ? 'permissionRequired' : 'installerOpened';
  }
  @override Future<void> permissionSettings() async { settings++; }
  @override Future<void> cancel() async { cancellations++; }
}

void main() {
  test('Only newer official APK releases with digest and bounded size are accepted', () {
    expect(ReleaseUpdate.fromJson(release(), 33)?.build, 40);
    expect(ReleaseUpdate.fromJson(release(), 40), isNull);
    expect(ReleaseUpdate.fromJson(release()..['draft'] = true, 33), isNull);
    expect(ReleaseUpdate.fromJson(release()..['prerelease'] = true, 33), isNull);
    for (final data in [
      release(download: url.toString().replaceFirst('https:', 'http:')),
      release(download: 'https://example.com/app.apk'),
      release(digest: 'sha256:bad'),
      release(size: maximumApkBytes + 1),
      release()..['assets'] = [],
    ]) {
      expect(() => ReleaseUpdate.fromJson(data, 33), throwsFormatException);
    }
  });

  test('Download redirects remain HTTPS on known GitHub asset hosts', () {
    expect(UpdateDownloader.trustedDownload(url), isTrue);
    expect(UpdateDownloader.trustedDownload(Uri.parse('https://release-assets.githubusercontent.com/a')), isTrue);
    for (final address in ['http://github.com/a', 'https://github.com.evil.test/a',
      'https://user:secret@github.com/a', 'https://github.com:444/a', 'https://127.0.0.1/a']) {
      expect(UpdateDownloader.trustedDownload(Uri.parse(address)), isFalse);
    }
  });

  test('APK is streamed, checked and atomically promoted only when complete', () async {
    final root = await Directory.systemTemp.createTemp('updater-test-');
    addTearDown(() => root.delete(recursive: true));
    final progress = <double>[];
    final file = await UpdateDownloader().save(fixture(),
      Stream.fromIterable([payload.sublist(0, 2), payload.sublist(2)]), root, progress.add);
    expect(await file.readAsBytes(), payload);
    expect(progress.last, 1);
    expect(await File('${file.path}.part').exists(), isFalse);
  });

  test('Truncated, oversized and corrupt files leave no installable or partial APK', () async {
    for (final update in [fixture(size: payload.length + 1),
        fixture(size: payload.length - 1), fixture(digest: '0' * 64)]) {
      final root = await Directory.systemTemp.createTemp('updater-test-');
      try {
        await expectLater(UpdateDownloader().save(update, Stream.value(payload), root, (_) {}),
          throwsFormatException);
        expect(await root.list().toList(), isEmpty);
      } finally { await root.delete(recursive: true); }
    }
  });

  test('Cancellation and broken streams remove partial downloads', () async {
    final root = await Directory.systemTemp.createTemp('updater-test-');
    addTearDown(() => root.delete(recursive: true));
    final downloader = UpdateDownloader()..cancel();
    await expectLater(downloader.save(fixture(), Stream.value(payload), root, (_) {}),
      throwsA(isA<UpdateCancelled>()));
    expect(await root.list().toList(), isEmpty);
    await expectLater(UpdateDownloader().save(fixture(),
      Stream<List<int>>.error(const SocketException('offline')), root, (_) {}), throwsA(isA<SocketException>()));
    expect(await root.list().toList(), isEmpty);
  });

  Future<void> openDialog(WidgetTester tester, FakeInstaller installer, FakeDownloader downloader) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () => showDialog<void>(context: context,
        builder: (_) => AppUpdateDialog(update: fixture(), installer: installer, downloader: downloader)),
        child: const Text('Update'))))));
    await tester.tap(find.text('Update'));
    // Real filesystem work is outside the fake test clock.
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 20));
      if (installer.installs > 0 || downloader.pending != null) break;
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('Permission refusal stays recoverable and return opens Android installer', (tester) async {
    final root = (await tester.runAsync(() => Directory.systemTemp.createTemp('updater-ui-')))!;
    addTearDown(() => root.delete(recursive: true));
    final installer = FakeInstaller(root);
    await openDialog(tester, installer, FakeDownloader(File('${root.path}/update-40.apk')));
    expect(find.text('Installation erlauben'), findsOneWidget);
    expect(installer.installs, 1);
    await tester.tap(find.text('Installation erlauben'));
    await tester.pump();
    expect(installer.settings, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Installation erlauben'), findsOneWidget);
    expect(installer.installs, 2);
    await tester.tap(find.text('Installation erlauben'));
    installer.permission = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(AppUpdateDialog), findsNothing);
    expect(installer.installs, 3);
  });

  testWidgets('Cancel closes the download and never opens the installer afterwards', (tester) async {
    final root = (await tester.runAsync(() => Directory.systemTemp.createTemp('updater-ui-')))!;
    addTearDown(() => root.delete(recursive: true));
    final installer = FakeInstaller(root);
    final pending = Completer<File>();
    final downloader = FakeDownloader(File('${root.path}/update-40.apk'), pending: pending);
    await openDialog(tester, installer, downloader);
    await tester.tap(find.text('Abbrechen'));
    expect(downloader.cancelled, isTrue);
    // Complete while the route is still mounted during its closing animation.
    pending.complete(downloader.file);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(installer.installs, 0);
    expect(find.byType(AppUpdateDialog), findsNothing);
  });
}
