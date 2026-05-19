// lib/modules/conditions/conditions_webview_screen.dart
//
// Écran plein écran qui héberge le frontend HTML de Névé dans une WebView.
//
// Approche WhiteSilence : on ne réinvente pas l'UI Conditions — on utilise
// telle quelle l'UI HTML/JS éprouvée du backend, servie à la racine de
// `https://snow-conditions.onrender.com/`. Cohérence 1:1 avec le site web.

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/secrets.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';

class ConditionsWebViewScreen extends StatefulWidget {
  const ConditionsWebViewScreen({super.key});

  @override
  State<ConditionsWebViewScreen> createState() =>
      _ConditionsWebViewScreenState();
}

class _ConditionsWebViewScreenState extends State<ConditionsWebViewScreen> {
  late final WebViewController _controller;
  int _progress = 0;
  bool _isReady = false;
  String? _loadError;

  String get _url => WSSecrets.neveFrontendUrl;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(WSColors.snowWhite)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _progress = p);
        },
        onPageFinished: (_) {
          if (!mounted) return;
          setState(() {
            _isReady = true;
            _progress = 100;
          });
        },
        onWebResourceError: (err) {
          if (!mounted) return;
          // Seules les erreurs sur la page principale nous intéressent
          if (err.isForMainFrame != true) return;
          setState(() {
            _loadError = err.description;
          });
        },
      ))
      ..loadRequest(Uri.parse(_url));
  }

  void _reload() {
    setState(() {
      _isReady   = false;
      _progress  = 0;
      _loadError = null;
    });
    _controller.loadRequest(Uri.parse(_url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WSColors.snowWhite,
      appBar: AppBar(
        title: const Text('Conditions de neige'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'Recharger',
            onPressed: _reload,
          ),
        ],
      ),
      body: _loadError != null
          ? _ErrorState(error: _loadError!, onRetry: _reload, url: _url)
          : Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (!_isReady)
                  Positioned(
                    top: 0, left: 0, right: 0,
                    child: LinearProgressIndicator(
                      value: _progress > 0 ? _progress / 100 : null,
                      minHeight: 2,
                      backgroundColor: WSColors.glacierLight,
                      valueColor: const AlwaysStoppedAnimation(
                        WSColors.glacierBlue,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final String url;
  final VoidCallback onRetry;
  const _ErrorState({
    required this.error,
    required this.url,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 48, color: WSColors.stoneGray),
            const SizedBox(height: 16),
            const Text(
              'Impossible de charger les conditions',
              style: WSText.heading,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(error, style: WSText.caption, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(url, style: WSText.micro, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}
