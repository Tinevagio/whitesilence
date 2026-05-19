// lib/modules/ideas/widgets/idea_detail_sheet.dart
//
// Bottom sheet riche affichant tous les détails d'une idée :
//   - Infos topo
//   - Météo détaillée
//   - BERA
//   - Détails IA (features 7j)
//   - Boutons cross-module : Calculer le temps, Voir conditions, Ouvrir Camptocamp
//
// C'est aussi le point d'entrée des switches vers d'autres modules WhiteSilence.

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/module_navigator.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../models/idea.dart';
import '../services/ideas_preferences.dart';

class IdeaDetailSheet extends StatelessWidget {
  final Idea idea;
  const IdeaDetailSheet({super.key, required this.idea});

  Color _beraColor(int? r) {
    switch (r) {
      case 1: return WSColors.powderGreen;
      case 2: return const Color(0xFFE8A93C);
      case 3: return WSColors.sunOrange;
      case 4: return WSColors.avalancheRed;
      case 5: return WSColors.slateDark;
      default: return WSColors.stoneGray;
    }
  }

  void _switchToTime(BuildContext context) {
    Navigator.of(context).pop();
    ModuleNavigator().switchToTimeWithTarget(idea.latLng);
  }

  void _switchToConditions(BuildContext context) {
    Navigator.of(context).pop();
    // Bbox ~5km autour du sommet (similaire au "fetch here" de Conditions)
    const halfDeg = 0.025;
    final sw = LatLng(idea.lat - halfDeg, idea.lon - halfDeg);
    final ne = LatLng(idea.lat + halfDeg, idea.lon + halfDeg);
    ModuleNavigator().switchToConditionsWithBbox(sw, ne);
  }

  Future<void> _openExternal(BuildContext context) async {
    final url = idea.url;
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Impossible d\'ouvrir : $url'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: WSColors.snowWhite,
          borderRadius: BorderRadius.vertical(top: Radius.circular(WSRadius.xl)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(
              WSSpacing.xl, WSSpacing.sm, WSSpacing.xl, WSSpacing.xl),
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: WSSpacing.lg),
                decoration: BoxDecoration(
                  color: WSColors.glacierMid,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Text(idea.name, style: WSText.title),
            const SizedBox(height: 2),
            Text(
              '${idea.massif} · ${idea.difficulty} · ${idea.exposition}',
              style: WSText.caption.copyWith(color: WSColors.stoneGray),
            ),
            const SizedBox(height: WSSpacing.lg),

            // Score IA mis en avant si présent
            if (idea.aiPicto != null && idea.aiQualite != null) ...[
              Container(
                padding: const EdgeInsets.all(WSSpacing.md),
                decoration: BoxDecoration(
                  color: WSColors.glacierLight,
                  borderRadius: BorderRadius.circular(WSRadius.md),
                ),
                child: Row(
                  children: [
                    Text(idea.aiPicto!, style: const TextStyle(fontSize: 28)),
                    const SizedBox(width: WSSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(idea.aiQualite!,
                            style: WSText.body.copyWith(
                              fontWeight: FontWeight.w700,
                            )),
                          if (idea.aiSaisonMode != null)
                            Text('Mode ${idea.aiSaisonMode}',
                              style: WSText.micro.copyWith(
                                color: WSColors.stoneGray,
                              )),
                        ],
                      ),
                    ),
                    if (idea.aiNote10 != null)
                      Text(
                        '${idea.aiNote10!.toStringAsFixed(1)}/10',
                        style: WSText.title.copyWith(
                          color: WSColors.glacierBlue,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: WSSpacing.lg),
            ],

            // Caractéristiques topo
            _SectionTitle('Itinéraire'),
            _DetailRow(
              icon: Icons.trending_up,
              label: 'Dénivelé positif',
              value: '${idea.denivelePositif.round()} m',
            ),
            _DetailRow(
              icon: Icons.explore_outlined,
              label: 'Exposition',
              value: idea.exposition,
            ),
            _DetailRow(
              icon: Icons.signal_cellular_alt,
              label: 'Difficulté',
              value: idea.difficulty,
            ),
            _DetailRow(
              icon: Icons.public,
              label: 'Source',
              value: idea.source ?? '—',
            ),

            const SizedBox(height: WSSpacing.lg),
            // Météo
            _SectionTitle('Météo (${idea.meteo.icon})'),
            _DetailRow(
              icon: Icons.thermostat,
              label: 'Température moyenne',
              value: '${idea.meteo.meanTemp.toStringAsFixed(1)} °C',
            ),
            _DetailRow(
              icon: Icons.cloudy_snowing,
              label: 'Neige cumulée',
              value: '${idea.meteo.totalSnow.toStringAsFixed(0)} cm',
            ),
            _DetailRow(
              icon: Icons.water_drop_outlined,
              label: 'Précipitation totale',
              value: '${idea.meteo.totalPrecip.toStringAsFixed(0)} mm',
            ),
            _DetailRow(
              icon: Icons.air,
              label: 'Vent max',
              value: '${idea.meteo.maxWind.toStringAsFixed(0)} km/h',
            ),

            // BERA
            if (idea.bera.risque != null) ...[
              const SizedBox(height: WSSpacing.lg),
              _SectionTitle('Bulletin avalanche (BERA)'),
              Container(
                padding: const EdgeInsets.all(WSSpacing.md),
                decoration: BoxDecoration(
                  color: _beraColor(idea.bera.risque).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(WSRadius.md),
                  border: Border.all(
                    color: _beraColor(idea.bera.risque).withOpacity(0.40),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber,
                        color: _beraColor(idea.bera.risque), size: 20),
                    const SizedBox(width: WSSpacing.sm),
                    Text(
                      'Risque ${idea.bera.risque}/5',
                      style: WSText.body.copyWith(
                        color: _beraColor(idea.bera.risque),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Détails IA (expander)
            if (idea.featuresDetail != null) ...[
              const SizedBox(height: WSSpacing.lg),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('Détails du score IA', style: WSText.body.copyWith(
                  fontWeight: FontWeight.w600,
                )),
                children: [
                  _DetailRow(
                    icon: Icons.ac_unit,
                    label: 'Temp. min 7j',
                    value: '${idea.featuresDetail!.tempMin7d.toStringAsFixed(1)} °C',
                  ),
                  _DetailRow(
                    icon: Icons.wb_sunny_outlined,
                    label: 'Temp. max 7j',
                    value: '${idea.featuresDetail!.tempMax7d.toStringAsFixed(1)} °C',
                  ),
                  _DetailRow(
                    icon: Icons.compare_arrows,
                    label: 'Amplitude thermique 7j',
                    value: '${idea.featuresDetail!.tempAmp7d.toStringAsFixed(1)} °C',
                  ),
                  _DetailRow(
                    icon: Icons.cloudy_snowing,
                    label: 'Neige 7j',
                    value: '${idea.featuresDetail!.snowfall7d.toStringAsFixed(0)} cm',
                  ),
                  _DetailRow(
                    icon: Icons.air,
                    label: 'Vent max 7j',
                    value: '${idea.featuresDetail!.windMax7d.toStringAsFixed(0)} km/h',
                  ),
                  _DetailRow(
                    icon: Icons.repeat,
                    label: 'Cycles gel/dégel 7j',
                    value: '${idea.featuresDetail!.freezeThawCycles7d}',
                  ),
                  _DetailRow(
                    icon: Icons.score,
                    label: 'Score hiver',
                    value:
                        idea.featuresDetail!.baseScore.toStringAsFixed(2),
                  ),
                  _DetailRow(
                    icon: Icons.wb_sunny,
                    label: 'Score printemps',
                    value:
                        idea.featuresDetail!.springScore.toStringAsFixed(2),
                  ),
                ],
              ),
            ],

            const SizedBox(height: WSSpacing.xl),
            // Actions sur mes listes personnelles. Observe les prefs pour
            // que les labels changent en live ("Ajouter" / "Retirer").
            ListenableBuilder(
              listenable: IdeasPreferences(),
              builder: (context, _) {
                final prefs = IdeasPreferences();
                final url = idea.url;
                if (url == null || url.isEmpty) return const SizedBox.shrink();
                final inWishlist = prefs.isInWishlist(url);
                final hidden     = prefs.isHidden(url);
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              if (inWishlist) {
                                prefs.removeFromWishlist(url);
                              } else {
                                prefs.addToWishlist(url);
                              }
                            },
                            icon: Icon(
                              inWishlist ? Icons.star : Icons.star_border,
                              size: 18,
                              color: inWishlist
                                  ? const Color(0xFFE8A93C)
                                  : null,
                            ),
                            label: Text(inWishlist
                                ? 'Dans ma wish-list'
                                : 'Ajouter à ma wish-list'),
                          ),
                        ),
                        const SizedBox(width: WSSpacing.sm),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              if (hidden) {
                                prefs.unhide(url);
                              } else {
                                // Fermer la sheet en masquant : l'idée
                                // disparaît du carousel, plus de raison de
                                // garder le détail ouvert.
                                prefs.hide(url);
                                Navigator.of(context).pop();
                              }
                            },
                            icon: Icon(
                              hidden
                                  ? Icons.visibility_off
                                  : Icons.visibility_off_outlined,
                              size: 18,
                              color: hidden ? WSColors.avalancheRed : null,
                            ),
                            label: Text(hidden ? 'Démasquer' : 'Masquer'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: WSSpacing.sm),
                  ],
                );
              },
            ),
            // Actions cross-module
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _switchToTime(context),
                    icon: const Icon(Icons.timer_outlined, size: 18),
                    label: const Text('Mon temps'),
                  ),
                ),
                const SizedBox(width: WSSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _switchToConditions(context),
                    icon: const Icon(Icons.layers_outlined, size: 18),
                    label: const Text('Conditions'),
                  ),
                ),
              ],
            ),
            if (idea.url != null) ...[
              const SizedBox(height: WSSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () => _openExternal(context),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(
                    idea.source == 'camptocamp'
                        ? 'Voir sur Camptocamp'
                        : 'Voir sur Skitour',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: WSSpacing.sm),
      child: Text(
        text,
        style: WSText.body.copyWith(
          fontWeight: FontWeight.w700,
          color: WSColors.slateDark,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow({
    required this.icon, required this.label, required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: WSColors.stoneGray),
          const SizedBox(width: WSSpacing.sm),
          Expanded(child: Text(label, style: WSText.body)),
          Text(value,
            style: WSText.body.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
