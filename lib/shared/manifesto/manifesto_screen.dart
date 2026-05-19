import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';

/// L'écran qui pose la philosophie de l'app.
/// Affiché au premier lancement, accessible depuis Réglages → À propos.
class ManifestoScreen extends StatelessWidget {
  const ManifestoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Le manifeste')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: WSSpacing.xl,
          vertical: WSSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: WSSpacing.lg),
            Text(
              'WhiteSilence',
              style: WSText.display.copyWith(fontSize: 36),
            ),
            const SizedBox(height: WSSpacing.sm),
            Text(
              'Ski de rando sans bruit.',
              style: WSText.caption.copyWith(
                fontSize: 14,
                color: WSColors.stoneGray,
              ),
            ),
            const SizedBox(height: WSSpacing.xxl),

            // ─── Intro perso ────────────────────────────────────────────
            Text('Pourquoi WhiteSilence', style: WSText.heading),
            const SizedBox(height: WSSpacing.md),
            Text(
              'Je skie en montagne depuis longtemps. Suffisamment pour savoir '
              'que ce qu\'on y vient chercher, c\'est le silence. La déconnexion. '
              'L\'air dans les poumons et la neige sous les peaux, rien d\'autre.',
              style: WSText.body.copyWith(height: 1.6),
            ),
            const SizedBox(height: WSSpacing.md),
            Text(
              'Pourtant, ces dernières années, tout s\'est mis à faire du bruit '
              'autour de nos sorties. Les apps nous demandent de créer des comptes, '
              'de partager nos traces, de comparer nos temps. Elles transforment '
              'des moments d\'engagement personnel en données. Des contemplations '
              'en performances.',
              style: WSText.body.copyWith(height: 1.6),
            ),
            const SizedBox(height: WSSpacing.md),
            Text(
              'WhiteSilence est l\'app que je voulais utiliser, et que je ne '
              'trouvais pas. Pas de compte, pas de classement, pas de partage '
              'forcé. Juste les outils dont un skieur autonome a vraiment besoin '
              'sur le terrain : les conditions du jour, le BERA, les temps de '
              'course, la carte qui marche hors-ligne, et de quoi noter ses '
              'observations à la voix sans sortir les mains des moufles.',
              style: WSText.body.copyWith(height: 1.6),
            ),
            const SizedBox(height: WSSpacing.md),
            Text(
              'Si tu cherches la même chose, elle est pour toi.',
              style: WSText.body.copyWith(
                height: 1.6,
                fontStyle: FontStyle.italic,
                color: WSColors.slateDark,
              ),
            ),
            const SizedBox(height: WSSpacing.xxl),

            // ─── Les 6 principes ────────────────────────────────────────
            Text('Les principes', style: WSText.heading),
            const SizedBox(height: WSSpacing.lg),

            _principle(
              icon: Icons.no_accounts_outlined,
              title: 'Pas d\'inscription',
              body: 'Aucun compte, aucun identifiant, aucun email. '
                  'Tu ouvres l\'app, tu skies.',
            ),
            _principle(
              icon: Icons.visibility_off_outlined,
              title: 'Pas de tracking',
              body: 'Aucune analytique, aucune télémétrie, aucun cookie. '
                  'Tes positions ne quittent jamais ton téléphone, '
                  'sauf si tu choisis explicitement de partager une observation.',
            ),
            _principle(
              icon: Icons.block,
              title: 'Pas de pub, pas de premium',
              body: 'L\'app est gratuite et le restera. '
                  'Ni publicité, ni achat in-app, ni version premium.',
            ),
            _principle(
              icon: Icons.public_off_outlined,
              title: 'Pas de leaderboard',
              body: 'Pas de classement, pas de score, pas de comparaison. '
                  'Tu n\'es pas en compétition avec qui que ce soit.',
            ),
            _principle(
              icon: Icons.wifi_off_outlined,
              title: 'Offline-first',
              body: 'En montagne, le réseau n\'est jamais garanti. '
                  'WhiteSilence fonctionne sans connexion : '
                  'cartes, calculs, observations, tout en local.',
            ),
            _principle(
              icon: Icons.code,
              title: 'Open source',
              body: 'Le code est public sous licence MIT. '
                  'Tu peux le lire, le modifier, l\'auditer.',
            ),

            const SizedBox(height: WSSpacing.xxl),
            Container(
              padding: const EdgeInsets.all(WSSpacing.xl),
              decoration: BoxDecoration(
                color: WSColors.glacierLight,
                borderRadius: BorderRadius.circular(WSRadius.lg),
              ),
              child: Text(
                '«\u00a0La seule trace, c\'est celle dans la neige.\u00a0»',
                style: WSText.title.copyWith(
                  fontStyle: FontStyle.italic,
                  color: WSColors.slateDark,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: WSSpacing.xxl),
          ],
        ),
      ),
    );
  }

  Widget _principle({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: WSSpacing.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: WSColors.glacierBlue),
          const SizedBox(width: WSSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: WSText.heading),
                const SizedBox(height: 4),
                Text(body, style: WSText.body),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
