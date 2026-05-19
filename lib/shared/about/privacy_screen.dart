// lib/shared/about/privacy_screen.dart
//
// Politique de confidentialité de WhiteSilence.
// Le texte ci-dessous est délibérément simple et lisible (pas du juridique
// opaque). Le contenu reflète exactement la réalité technique : on ne
// collecte rien, on ne tracke rien, tout est local.
//
// Cette même politique sera publiée en HTML sur GitHub Pages pour que le
// Play Store puisse la référencer par URL (obligatoire si l'app demande
// des permissions sensibles comme GPS / micro).

import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confidentialité')),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: WSSpacing.xl,
          vertical: WSSpacing.lg,
        ),
        children: [
          _para(
            'En une phrase : WhiteSilence ne collecte aucune donnée '
            'personnelle. Tout reste sur ton téléphone.',
            bold: true,
          ),
          _h('Ce que l\'app utilise sur ton téléphone'),
          _li('Ta position GPS, pour t\'afficher sur la carte et calculer '
              'les temps de trajet (isochrones). La position n\'est jamais '
              'envoyée à un serveur.'),
          _li('Le micro, uniquement quand tu enregistres une observation '
              'vocale. L\'enregistrement est transcrit localement (ou via '
              'un service d\'API si tu actives cette option dans les '
              'Réglages) puis stocké sur ton téléphone.'),
          _li('Le stockage local, pour mémoriser tes observations, tes '
              'préférences, tes sorties favorites et les tuiles topo '
              'téléchargées pour usage hors-ligne.'),

          _h('Ce que l\'app envoie à des serveurs'),
          _para(
            'Pour fonctionner, WhiteSilence appelle des serveurs publics :',
          ),
          _li('Serveurs de cartographie (OpenStreetMap, OpenTopoMap) pour '
              'télécharger les tuiles de carte que tu visualises.'),
          _li('Serveur Météo France / Open-Meteo pour récupérer les '
              'conditions et le BERA du jour.'),
          _li('Backend WhiteSilence (snow-conditions.onrender.com et '
              'ski-touring-api.onrender.com) pour les modules Conditions '
              'et Idées de sortie. Ces backends reçoivent uniquement les '
              'coordonnées de la zone que tu consultes — pas d\'identifiant.'),
          _para(
            'Ces requêtes peuvent apparaître dans les logs techniques des '
            'serveurs concernés (adresse IP, horodatage), comme pour '
            'n\'importe quel site web. WhiteSilence ne joint pas '
            'd\'identifiant à ces requêtes : impossible de les corréler à '
            'un utilisateur particulier.',
          ),

          _h('Ce que l\'app NE fait PAS'),
          _li('Aucun compte utilisateur, aucune inscription, aucun email.'),
          _li('Aucune analytique (pas de Firebase, pas de Google Analytics, '
              'pas de Sentry, pas de Mixpanel, rien).'),
          _li('Aucune publicité, aucun partenaire commercial.'),
          _li('Aucun partage de tes positions ou de tes observations '
              'sans action explicite de ta part.'),
          _li('Aucun classement, aucun leaderboard, aucune comparaison '
              'avec d\'autres utilisateurs.'),

          _h('Données partagées explicitement'),
          _para(
            'Si tu actives la fonction "partager une observation" depuis '
            'le module Neige, ton observation (texte transcrit, position, '
            'horodatage) sera envoyée à la base communautaire Supabase. '
            'C\'est anonyme — pas d\'identifiant utilisateur — mais ces '
            'observations sont publiquement consultables. Tu peux désactiver '
            'cette fonction à tout moment dans les Réglages.',
          ),

          _h('Tes droits'),
          _para(
            'Vu qu\'aucune donnée personnelle ne quitte ton téléphone, '
            'il n\'y a pas grand-chose à demander à WhiteSilence en termes '
            'de droits RGPD. Pour effacer toutes tes données, il suffit de '
            'désinstaller l\'app — rien ne restera derrière.',
          ),

          _h('Open source'),
          _para(
            'Le code de WhiteSilence est public sous licence MIT. Tu peux '
            'vérifier toutes ces affirmations en lisant le code sur GitHub.',
          ),

          _h('Contact'),
          _para(
            'Pour toute question concernant cette politique : ouvre une '
            'issue sur le repo GitHub de WhiteSilence.',
          ),

          const SizedBox(height: WSSpacing.xl),
          Center(
            child: Text(
              'Dernière mise à jour : ${_today()}',
              style: WSText.micro.copyWith(color: WSColors.stoneGray),
            ),
          ),
          const SizedBox(height: WSSpacing.xl),
        ],
      ),
    );
  }

  static String _today() {
    final now = DateTime.now();
    const months = [
      'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
      'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
    ];
    return '${now.day} ${months[now.month - 1]} ${now.year}';
  }

  Widget _h(String text) => Padding(
        padding: const EdgeInsets.only(top: WSSpacing.xl, bottom: WSSpacing.sm),
        child: Text(text, style: WSText.heading),
      );

  Widget _para(String text, {bool bold = false}) => Padding(
        padding: const EdgeInsets.only(top: WSSpacing.sm),
        child: Text(
          text,
          style: WSText.body.copyWith(
            fontWeight: bold ? FontWeight.w600 : null,
            height: 1.5,
          ),
        ),
      );

  Widget _li(String text) => Padding(
        padding: const EdgeInsets.only(top: WSSpacing.sm, left: WSSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('· ', style: WSText.body.copyWith(color: WSColors.glacierBlue)),
            Expanded(
              child: Text(text, style: WSText.body.copyWith(height: 1.5)),
            ),
          ],
        ),
      );
}
