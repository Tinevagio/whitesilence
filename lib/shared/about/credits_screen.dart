// lib/shared/about/credits_screen.dart
//
// Crédits & licences des sources de données + bibliothèques tierces.
// Important pour :
//   - Respect des licences OSM (attribution obligatoire en CC-BY-SA)
//   - Transparence sur d'où viennent les conditions affichées
//   - Pour le Play Store et l'open-sourcing.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';

class CreditsScreen extends StatelessWidget {
  const CreditsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crédits & sources')),
      body: ListView(
        padding: const EdgeInsets.all(WSSpacing.lg),
        children: [
          _intro(
            'WhiteSilence repose sur le travail d\'autres projets, '
            'organismes publics et communautés open source. Merci à eux.',
          ),
          const SizedBox(height: WSSpacing.xl),

          _section('Cartographie'),
          _CreditTile(
            title: 'OpenStreetMap',
            subtitle: 'Cartographie collaborative mondiale. '
                '© Les contributeurs OpenStreetMap, licence ODbL.',
            url: 'https://www.openstreetmap.org/copyright',
          ),
          _CreditTile(
            title: 'OpenTopoMap',
            subtitle: 'Style cartographique topographique optimisé montagne. '
                'CC-BY-SA 3.0.',
            url: 'https://opentopomap.org/',
          ),

          _section('Conditions de neige & avalanche'),
          _CreditTile(
            title: 'Météo France — BERA',
            subtitle: 'Bulletin d\'estimation du risque d\'avalanche, '
                'publié quotidiennement pour les massifs français.',
            url: 'https://meteofrance.com/meteo-montagne/avalanches',
          ),
          _CreditTile(
            title: 'Open-Meteo',
            subtitle: 'API météo libre, données historiques et prévisions '
                'horaires. CC-BY 4.0.',
            url: 'https://open-meteo.com/',
          ),

          _section('Itinéraires de ski de rando'),
          _CreditTile(
            title: 'Camptocamp.org',
            subtitle: 'Topo-guides communautaires de courses en montagne. '
                'Licence CC-BY-SA.',
            url: 'https://www.camptocamp.org/',
          ),
          _CreditTile(
            title: 'Skitour',
            subtitle: 'Base de données et récits de sorties ski de rando.',
            url: 'https://www.skitour.fr/',
          ),

          _section('Données topographiques'),
          _CreditTile(
            title: 'SRTM (NASA)',
            subtitle: 'Modèle numérique de terrain mondial à 30 m. '
                'Domaine public.',
            url: 'https://www.earthdata.nasa.gov/sensors/srtm',
          ),

          _section('Logiciels'),
          _CreditTile(
            title: 'Flutter',
            subtitle: 'Framework UI cross-platform de Google.',
            url: 'https://flutter.dev/',
          ),
          _CreditTile(
            title: 'flutter_map',
            subtitle: 'Bibliothèque de cartographie Flutter open source.',
            url: 'https://pub.dev/packages/flutter_map',
          ),

          const SizedBox(height: WSSpacing.xl),
          Container(
            padding: const EdgeInsets.all(WSSpacing.md),
            decoration: BoxDecoration(
              color: WSColors.glacierLight,
              borderRadius: BorderRadius.circular(WSRadius.md),
            ),
            child: Text(
              'La liste complète des bibliothèques tierces et leurs licences '
              'est disponible dans le code source sur GitHub.',
              style: WSText.micro.copyWith(color: WSColors.stoneGray),
            ),
          ),
          const SizedBox(height: WSSpacing.xl),
        ],
      ),
    );
  }

  Widget _intro(String text) => Padding(
        padding: const EdgeInsets.only(top: WSSpacing.sm),
        child: Text(text, style: WSText.body),
      );

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: WSSpacing.xl, bottom: WSSpacing.sm),
        child: Text(
          title,
          style: WSText.heading.copyWith(color: WSColors.slateDark),
        ),
      );
}

class _CreditTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String url;
  const _CreditTile({
    required this.title,
    required this.subtitle,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication),
      borderRadius: BorderRadius.circular(WSRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: WSSpacing.xs, vertical: WSSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: WSText.body
                          .copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style:
                          WSText.micro.copyWith(color: WSColors.stoneGray)),
                ],
              ),
            ),
            const SizedBox(width: WSSpacing.sm),
            const Icon(Icons.open_in_new,
                size: 16, color: WSColors.stoneGray),
          ],
        ),
      ),
    );
  }
}
