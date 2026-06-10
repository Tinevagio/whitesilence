// lib/shared/help/help_screen.dart

import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WSColors.snowWhite,
      appBar: AppBar(
        backgroundColor: WSColors.snowWhite,
        elevation: 0,
        title: const Text('Comment ça marche ?'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            WSSpacing.lg, 0, WSSpacing.lg, WSSpacing.xl),
        children: const [
          _Intro(),
          SizedBox(height: WSSpacing.xl),
          _Section(
            icon: Icons.schedule_outlined,
            color: WSColors.glacierBlue,
            title: 'Temps & Itinéraire',
            entries: [
              _Entry(
                title: 'Isochrones',
                body: 'Des cercles de temps qui s\'étendent depuis ta position GPS. '
                    'La zone verte = ce que tu peux atteindre en 15 min, bleue en 30 min, '
                    'orange en 45 min, rouge en 60 min. '
                    'Tape "Calculer les isochrones" pour les afficher.',
              ),
              _Entry(
                title: 'Calibration Munter',
                body: 'WhiteSilence apprend ta vitesse réelle en marchant. '
                    'Plus tu te déplaces, plus les estimations de temps s\'ajustent à ton rythme personnel. '
                    'La barre en bas du panneau montre l\'état de la calibration.',
              ),
              _Entry(
                title: 'Itinéraire Auto',
                body: 'En mode "Auto", tape un point de départ puis un point d\'arrivée sur la carte. '
                    'L\'appli calcule un tracé qui suit les vrais sentiers et pistes balisées, '
                    'sans réseau. La distance, le dénivelé et le temps estimé s\'affichent aussitôt.',
              ),
              _Entry(
                title: 'Itinéraire Main levée',
                body: 'En mode "Main levée", fais glisser le doigt sur la carte pour dessiner '
                    'ton propre tracé. Pratique pour les itinéraires hors-sentier ou quand '
                    'le chemin n\'est pas encore cartographié.',
              ),
              _Entry(
                title: 'Long-press sur la carte',
                body: 'Maintiens le doigt appuyé sur un point pour épingler une origine custom '
                    'pour les isochrones. Utile pour planifier depuis un refuge ou un col '
                    'sans être physiquement sur place.',
              ),
            ],
          ),
          SizedBox(height: WSSpacing.lg),
          _Section(
            icon: Icons.camera_alt_outlined,
            color: WSColors.powderGreen,
            title: 'Observations',
            entries: [
              _Entry(
                title: 'Enregistrer une observation',
                body: 'Dicte ou tape une observation nivo : qualité de la neige, '
                    'exposition du versant, signes d\'avalanche récents, conditions de ski. '
                    'Elle est stockée localement, géolocalisée, et jamais partagée sans ton accord.',
              ),
              _Entry(
                title: 'Consulter les observations',
                body: 'Les flocons sur la carte montrent tes observations passées. '
                    'Tu peux les modifier après coup. '
                    'En mode mains libres, tu peux activer l\'enregistrement en disant "Hey Snowy", '
                    'et couper avec "Bye Bye Snowy". '
                    'Tape sur un flocon pour relire le détail de l\'enregistrement.',
              ),
            ],
          ),
          SizedBox(height: WSSpacing.lg),
          _Section(
            icon: Icons.cloud_outlined,
            color: WSColors.sunOrange,
            title: 'Conditions',
            entries: [
              _Entry(
                title: 'Carte des conditions',
                body: 'Dessine une box autour de la zone où tu comptes skier. '
                    'Tu verras alors la simulation d\'évolution du manteau neigeux au cours de la journée. '
                    'Tu peux décider de ne voir que le meilleur créneau de poudreuse ou de moquette.',
              ),
              _Entry(
                title: 'Simulation des avalanches',
                body: 'Tu vois sur le terrain la projection des cônes d\'avalanche. '
                    'Le bulletin météo-nivo du massif le plus proche est mis à jour chaque jour en fin de journée. '
                    'On indique le niveau de risque (1 faible → 5 très fort).',
              ),
              _Entry(
                title: 'Carte enneigement',
                body: 'Une heatmap de l\'enneigement basée sur les données météo récentes.',
              ),
              _Entry(
                title: 'Fetch "Ici"',
                body: 'Le bouton cible charge les conditions précises autour de ta position GPS, '
                    'même si tu as zoomé ailleurs sur la carte.',
              ),
            ],
          ),
          SizedBox(height: WSSpacing.lg),
          _Section(
            icon: Icons.lightbulb_outline,
            color: WSColors.avalancheRed,
            title: 'Idées de sorties',
            entries: [
              _Entry(
                title: 'Suggestions personnalisées',
                body: 'Des itinéraires proposés selon les conditions du jour, '
                    'le niveau de risque avalanche et ta zone géographique. '
                    'Tape une suggestion pour la voir sur la carte. '
                    'Tu peux activer le scoring IA qui pousse un peu plus loin la skiabilité de la sortie.',
              ),
            ],
          ),
          SizedBox(height: WSSpacing.lg),
          _Section(
            icon: Icons.layers_outlined,
            color: WSColors.stoneGray,
            title: 'Zones hors-ligne',
            entries: [
              _Entry(
                title: 'Télécharger une zone',
                body: 'Réglages → Zones hors-ligne. Chaque case sur la carte couvre ~100×100 km. '
                    'Télécharge les zones de tes sorties habituelles sur WiFi. '
                    'Une fois installées, la carte topo, les isochrones et les itinéraires '
                    'fonctionnent sans aucune connexion.',
              ),
              _Entry(
                title: 'Données altitude vs itinéraire',
                body: 'Chaque zone a deux couches : altitude (pour les isochrones et le dénivelé) '
                    'et routage (pour les itinéraires qui suivent les sentiers). '
                    'Le vert = les deux sont installés. Le bleu = altitude seule.',
              ),
            ],
          ),
          SizedBox(height: WSSpacing.lg),
          _PhilosophyBox(),
          SizedBox(height: WSSpacing.xl),
        ],
      ),
    );
  }
}

// ── Intro ─────────────────────────────────────────────────────────────────────

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(WSSpacing.lg),
      decoration: BoxDecoration(
        color: WSColors.glacierBlueBg,
        borderRadius: BorderRadius.circular(WSRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo
          Image.asset(
            'assets/images/logo_mountain.png',
            height: 48,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
          ),
          const SizedBox(height: WSSpacing.md),
          Text(
            'Une appli de ski de randonnée pour le terrain, '
            'entièrement gratuite et sans compte. '
            'La seule trace, c\'est celle dans la neige.',
            style: WSText.body.copyWith(color: WSColors.glacierBlue),
          ),
        ],
      ),
    );
  }
}

// ── Section ───────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final List<_Entry> entries;

  const _Section({
    required this.icon,
    required this.color,
    required this.title,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: WSSpacing.md),
            Text(title,
                style: WSText.heading.copyWith(color: WSColors.slateDark)),
          ],
        ),
        const SizedBox(height: WSSpacing.md),
        ...entries.map((e) => _EntryTile(entry: e, accentColor: color)),
      ],
    );
  }
}

// ── Entrée ────────────────────────────────────────────────────────────────────

class _Entry {
  final String title;
  final String body;
  const _Entry({required this.title, required this.body});
}

class _EntryTile extends StatefulWidget {
  final _Entry entry;
  final Color accentColor;
  const _EntryTile({required this.entry, required this.accentColor});

  @override
  State<_EntryTile> createState() => _EntryTileState();
}

class _EntryTileState extends State<_EntryTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        margin: const EdgeInsets.only(bottom: WSSpacing.sm),
        decoration: BoxDecoration(
          color: _expanded
              ? widget.accentColor.withOpacity(0.05)
              : WSColors.snowWhite,
          borderRadius: BorderRadius.circular(WSRadius.md),
          border: Border.all(
            color: _expanded
                ? widget.accentColor.withOpacity(0.3)
                : WSColors.glacierMid.withOpacity(0.5),
            width: 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  WSSpacing.md, WSSpacing.md, WSSpacing.sm, WSSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.entry.title,
                      style: WSText.body.copyWith(
                        fontWeight: FontWeight.w500,
                        color: _expanded
                            ? widget.accentColor
                            : WSColors.slateDark,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                    color: WSColors.stoneGray,
                  ),
                ],
              ),
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    WSSpacing.md, 0, WSSpacing.md, WSSpacing.md),
                child: Text(
                  widget.entry.body,
                  style: WSText.body
                      .copyWith(color: WSColors.slateDark, height: 1.5),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Boîte philosophie ─────────────────────────────────────────────────────────

class _PhilosophyBox extends StatelessWidget {
  const _PhilosophyBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(WSSpacing.lg),
      decoration: BoxDecoration(
        color: WSColors.slateDark,
        borderRadius: BorderRadius.circular(WSRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Philosophie',
            style: WSText.title.copyWith(color: WSColors.snowWhite),
          ),
          const SizedBox(height: WSSpacing.md),
          Text(
            '• Aucun compte requis\n'
            '• Aucune donnée personnelle collectée\n'
            '• Open source (MIT)',
            style: WSText.body.copyWith(
                color: WSColors.snowWhite.withOpacity(0.85), height: 1.7),
          ),
          const SizedBox(height: WSSpacing.md),
          Text(
            '"La seule trace, c\'est celle dans la neige."',
            style: WSText.caption.copyWith(
              color: WSColors.glacierBlueLight,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
