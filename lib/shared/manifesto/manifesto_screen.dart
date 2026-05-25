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
			  'j\'ai compris que nous y cherchons des expériences '
			  'qu\'aucun autre lieu ne sait offrir. Cette sensation '
			  'incroyable de flotter au-dessus d\'une neige poudreuse, '
			  'légère comme une poussière de lumière. La montagne '
			  'efface le monde d\'en bas. Elle ralentit le temps. '
			  'Chaque virage devient un silence.',
			  style: WSText.body.copyWith(height: 1.6),
			),
			const SizedBox(height: WSSpacing.md),
			Text(
			  'Parfois, au petit matin, la pente est encore intacte. '
			  'La neige repose là, lisse, parfaite, presque fragile '
			  'sous le ciel froid. Elle a quelque chose d\'endormi. '
			  'On avance alors avec précaution, comme si la montagne '
			  'retenait son souffle sous nos pas.',
			  style: WSText.body.copyWith(height: 1.6),
			),
			const SizedBox(height: WSSpacing.md),
			Text(
			  'Mais l\'instant d\'après, elle rappelle sa puissance. '
			  'La chaleur lourde d\'une pente sud au printemps, quand '
			  'le manteau se fissure doucement sous le soleil. Puis '
			  'l\'ombre brusque d\'un couloir nord, le froid sec qui '
			  'saisit la poitrine, le doute qui revient. Le cœur '
			  'accélère avant un passage exposé. Là-haut, l\'erreur '
			  'ne pardonne jamais vraiment.',
			  style: WSText.body.copyWith(height: 1.6),
			),
			const SizedBox(height: WSSpacing.md),
			Text(
			  'J\'ai créé WhiteSilence pour alléger cette tension '
			  'invisible. Je voulais un compagnon discret, capable de '
			  'veiller pendant que l\'esprit retrouve sa liberté. Une '
			  'application pensée pour lire l\'évolution du manteau '
			  'neigeux heure après heure, visualiser les risques '
			  'd\'avalanche directement sur la carte et estimer '
			  'simplement les temps de parcours.',
			  style: WSText.body.copyWith(height: 1.6),
			),
			const SizedBox(height: WSSpacing.md),
			Text(
			  'WhiteSilence rassemble les observations les plus '
			  'récentes et les plus précises, exactement là où tu te '
			  'trouves. Pour que, lorsque tout devient silencieux '
			  'autour de toi, il ne reste plus qu\'une chose : la '
			  'beauté pure du mouvement dans la montagne.',
			  style: WSText.body.copyWith(height: 1.6),
			),
			const SizedBox(height: WSSpacing.md),
			Text(
			  'Une fois l\'esprit apaisé, la montagne redevient ce '
			  'qu\'elle a toujours été : un espace de grâce. La neige '
			  'recommence à parler sous les skis avec cette douceur '
			  'presque irréelle des grands jours d\'hiver. Une courbe '
			  'lente tracée dans une pente vierge suffit alors à '
			  'remplir le silence.',
			  style: WSText.body.copyWith(height: 1.6),
			),
			const SizedBox(height: WSSpacing.md),
			Text(
			  'Si tu cherches toi aussi cette clarté-là, celle où le '
			  'corps avance sans bruit et où l\'esprit cesse enfin de '
			  'lutter, alors cette application est faite pour toi.',
			  style: WSText.body.copyWith(height: 1.6),
			),
			const SizedBox(height: WSSpacing.md),
			Text(
			  'Ici, rien ne te suit. Aucun compte. Aucun identifiant. '
			  'Aucune mémoire cachée de ton passage. La montagne n\'a '
			  'jamais demandé ton adresse e-mail pour t\'accueillir au '
			  'lever du jour, ni ton consentement pour ouvrir devant '
			  'toi une pente intacte.',
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
