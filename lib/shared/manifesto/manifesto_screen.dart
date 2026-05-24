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
              'Je skie en montagne depuis toujours, et avec les années, '
              'j\'ai compris que nous y cherchons des expériences brutes '
              'qu\'on ne trouve nulle part ailleurs. Cette sensation '
              'incroyable de voler au-dessus de trente centimètres de '
              'poudreuse légère, ou de savourer la souplesse parfaite '
              'd\'une belle neige de printemps. On oublie le bruit d\'en '
              'bas. On respire.',
              style: WSText.body.copyWith(height: 1.6),
            ),
            const SizedBox(height: WSSpacing.md),
            Text(
              'Pourtant, l\'instant d\'après, la montagne nous rappelle '
              'sa gravité. C\'est la chaleur étouffante d\'une pente sud '
              'en mai, quand la neige décolle sous le soleil. Puis, dès '
              'qu\'on bascule dans l\'ombre, le froid glacial d\'un '
              'couloir nord qui te saisit l\'échine. Dans ces '
              'moments-là, on est seul avec ses doutes. Avec la peur '
              'sourde de se faire coffrer, le cœur qui s\'accélère avant '
              'un virage engagé au-dessus du vide, là où on sait que '
              'l\'erreur ne pardonne pas.',
              style: WSText.body.copyWith(height: 1.6),
            ),
            const SizedBox(height: WSSpacing.md),
            Text(
              'J\'ai créé WhiteSilence pour apaiser cette part d\'ombre. '
              'Je voulais un compagnon discret qui prenne l\'inquiétude '
              'à sa charge pour libérer l\'esprit. L\'application est là '
              'pour t\'aider à lire l\'évolution du manteau neigeux au '
              'fil des heures, à visualiser les risques d\'avalanche '
              'directement sur la carte, et à simuler simplement tes '
              'temps de parcours. Elle met à ta portée les '
              'observations les plus récentes et les plus précises, pile '
              'sur ton point GPS.',
              style: WSText.body.copyWith(height: 1.6),
            ),
            const SizedBox(height: WSSpacing.md),
            Text(
              'Une fois l\'esprit serein, le miracle de la glisse revient.',
              style: WSText.body.copyWith(height: 1.6),
            ),
            const SizedBox(height: WSSpacing.md),
            Text(
              'Si tu cherches toi aussi cette clarté, et le plaisir '
              'd\'une courbe tracée dans le silence… cette application '
              'est pour toi.',
              style: WSText.body.copyWith(height: 1.6),
            ),
            const SizedBox(height: WSSpacing.md),
            Text(
              'Pas de compte, pas d\'e-mail, pas de compétition. '
              'Aucune trace de ton passage.',
              style: WSText.body.copyWith(height: 1.6),
            ),
            const SizedBox(height: WSSpacing.md),
            Text(
              'Libre, enfin.',
              style: WSText.body.copyWith(
                height: 1.6,
                fontStyle: FontStyle.italic,
                color: WSColors.slateDark,
                fontWeight: FontWeight.w600,
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
