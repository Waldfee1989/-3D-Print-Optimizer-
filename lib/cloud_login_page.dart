import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'anycubic_cloud.dart';

class CloudLoginResult {
  const CloudLoginResult(this.token, this.userAgent);
  final String token;
  final String? userAgent;
}

class CloudLoginPage extends StatefulWidget {
  const CloudLoginPage({super.key});
  @override State<CloudLoginPage> createState() => _CloudLoginPageState();
}
class _CloudLoginPageState extends State<CloudLoginPage> {
  late final WebViewController controller;
  String host = cloudApiHost;
  String? error;
  int progress = 0;
  bool reading = false;
  @override void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (value) { if (mounted) setState(() => progress = value); },
        onPageStarted: (url) { if (mounted) setState(() { host = Uri.tryParse(url)?.host ?? ''; error = null; }); },
        onWebResourceError: (failure) { if (mounted && failure.isForMainFrame == true) setState(() => error = 'Anmeldeseite konnte nicht geladen werden. Bitte erneut versuchen.'); },
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri != null && cloudLoginNavigation(uri)) return NavigationDecision.navigate;
          if (mounted) setState(() => error = 'Diese Weiterleitung gehört nicht zur unterstützten Anmeldung.');
          return NavigationDecision.prevent;
        },
      ))
      ..loadRequest(Uri.https(cloudApiHost, '/file'));
  }
  Future<void> useSession() async {
    if (reading) return;
    setState(() { reading = true; error = null; });
    try {
      final uri = Uri.tryParse(await controller.currentUrl() ?? '');
      if (uri == null || uri.scheme != 'https' || uri.host != cloudApiHost || uri.port != 443 || uri.userInfo.isNotEmpty) {
        throw const FormatException('Bitte die Anmeldung abschließen und zur Anycubic-Dateiseite zurückkehren.');
      }
      // Explicit user action; read just the provider's current session value.
      // No password fields, cookies, form input, or other storage is inspected.
      final value = await controller.runJavaScriptReturningResult("window.location.origin === 'https://cloud-universe.anycubic.com' ? (window.localStorage.getItem('XX-Token') || '') : ''");
      final token = cloudSessionToken(value);
      final agentValue = await controller.runJavaScriptReturningResult('navigator.userAgent');
      var agent = '$agentValue';
      if (agent.startsWith('"')) { try { agent = jsonDecode(agent) as String; } catch (_) { agent = ''; } }
      if (mounted) Navigator.pop(context, CloudLoginResult(token, agent.isEmpty ? null : agent));
    } on FormatException catch (e) { if (mounted) setState(() => error = e.message);
    } catch (_) { if (mounted) setState(() => error = 'Die angemeldete Sitzung konnte nicht übernommen werden. Bitte erneut anmelden.');
    } finally { if (mounted) setState(() => reading = false); }
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Bei Anycubic anmelden'), actions: [IconButton(tooltip: 'Neu laden', onPressed: () => controller.reload(), icon: const Icon(Icons.refresh))]),
    body: SafeArea(child: Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Text('Offizielle Anmeldeseite: $host\nMelde dich hier bei Anycubic International an. Nach der Rückkehr zur Dateiseite unten „Konto verbinden“ wählen.')),
      if (progress < 100) LinearProgressIndicator(value: progress / 100),
      Expanded(child: WebViewWidget(controller: controller)),
      if (error != null) Padding(padding: const EdgeInsets.all(12), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      Padding(padding: const EdgeInsets.all(12), child: FilledButton.icon(onPressed: reading ? null : useSession,
        icon: const Icon(Icons.account_circle_outlined), label: Text(reading ? 'Sitzung wird übernommen …' : 'Konto verbinden'))),
    ])),
  );
}
