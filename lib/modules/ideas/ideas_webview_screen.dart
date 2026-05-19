// lib/modules/ideas/ideas_webview_screen.dart
//
// Écran plein écran qui héberge l'app Streamlit "Ski Touring Live".
//
// Approche identique au module Conditions : on charge l'app web hébergée
// (Streamlit Cloud dans ce cas) dans une WebView in-app. Un seul code à
// maintenir côté Streamlit, l'app WhiteSilence suit automatiquement.
//
// Source : https://github.com/Tinevagio/Ski-touring-live
// Déploiement : https://ski-touring-live.streamlit.app

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/secrets.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';

class IdeasWebViewScreen extends StatefulWidget {
  const IdeasWebViewScreen({super.key});

  @override
  State<IdeasWebViewScreen> createState() => _IdeasWebViewScreenState();
}

class _IdeasWebViewScreenState extends State<IdeasWebViewScreen> {
  late final WebViewController _controller;
  int _progress = 0;
  bool _isReady = false;
  String? _loadError;

  // L'URL vient de .env (IDEAS_URL) avec fallback Streamlit Cloud.
  String get _url => WSSecrets.ideasUrl;

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
        title: const Text('Idées de sortie'),
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
                // Streamlit Cloud a aussi un cold start (~30s) — on prévient
                if (!_isReady && _progress < 15)
                  const Positioned(
                    top: 24, left: 0, right: 0,
                    child: Center(
                      child: _WakingUpHint(),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _WakingUpHint extends StatelessWidget {
  const _WakingUpHint();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: WSColors.snowWhite.withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WSColors.glacierMid, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          SizedBox(
            width: 12, height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              valueColor: AlwaysStoppedAnimation(WSColors.glacierBlue),
            ),
          ),
          SizedBox(width: 10),
          Text(
            'Streamlit met ~30s à se réveiller…',
            style: TextStyle(
              fontSize: 12,
              color: WSColors.slateDark,
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
              'Impossible de charger les idées',
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
