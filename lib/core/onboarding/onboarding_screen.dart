// lib/core/onboarding/onboarding_screen.dart
//
// Onboarding à la 1ère exécution (et après reset manuel). 3 pages :
//   1. Présentation philo : sans inscription, sans tracking, open source
//   2. Données locales + GPS (explications)
//   3. Modules vocaux
//
// Le bouton final "Commencer" marque l'onboarding comme vu et bascule sur
// l'app principale (WSShell).
//
// ── Permissions GPS ─────────────────────────────────────────────────────────
//
// On NE demande plus la permission GPS ici. C'est GpsService.start() qui s'en
// charge, via _startGpsAfterFrame() dans main.dart, juste après la fin de
// l'onboarding. Demander la permission depuis deux endroits (ici + GpsService)
// provoquait une double requête : Android avalait silencieusement la seconde et
// la permission restait bloquée en "denied" sans que le dialogue réapparaisse.
//
// Flux corrigé :
//   OnboardingScreen._finish()
//     → OnboardingService.markSeen()
//     → widget.onFinished()           (rappelle _AppEntrypointState)
//       → _startGpsAfterFrame()
//         → GpsService().start()      (unique source de vérité pour les perms)

import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'onboarding_service.dart';

class OnboardingScreen extends StatefulWidget {
  /// Callback appelé quand l'utilisateur a terminé. Le widget parent doit
  /// alors remplacer cette page par l'app principale.
  final VoidCallback onFinished;
  const OnboardingScreen({super.key, required this.onFinished});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;
  bool _finishing = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WSColors.snowWhite,
      body: SafeArea(
        child: Column(
          children: [
            // Pages
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: const [
                  _Page1Philosophy(),
                  _Page2LocalData(),
                  _Page3Voice(),
                ],
              ),
            ),

            // Indicateurs de page (3 points)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: WSSpacing.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == _currentPage ? 20 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _currentPage
                        ? WSColors.glacierBlue
                        : WSColors.glacierMid,
                    borderRadius: BorderRadius.circular(4),
                  ),
                )),
              ),
            ),

            // Boutons "Passer" / "Suivant" / "Commencer"
            Padding(
              padding: const EdgeInsets.fromLTRB(
                WSSpacing.lg, 0, WSSpacing.lg, WSSpacing.lg,
              ),
              child: Row(
                children: [
                  if (_currentPage < 2)
                    TextButton(
                      onPressed: _finishing ? null : _finish,
                      child: const Text('Passer'),
                    )
                  else
                    const SizedBox(width: 88),
                  const Spacer(),
                  if (_currentPage < 2)
                    FilledButton(
                      onPressed: _next,
                      child: const Text('Suivant'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _finishing ? null : _finish,
                      icon: _finishing
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.arrow_forward),
                      label: const Text('Commencer'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _next() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// Termine l'onboarding — que l'utilisateur ait cliqué "Commencer" ou
  /// "Passer". On NE demande plus de permission ici : GpsService.start()
  /// s'en charge seul juste après (voir commentaire en tête de fichier).
  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);

    await OnboardingService().markSeen();
    if (mounted) widget.onFinished();
  }
}

// ─── Page 1 : philosophie ───────────────────────────────────────────────────

class _Page1Philosophy extends StatelessWidget {
  const _Page1Philosophy();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WSSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Logo WS centré, taille généreuse pour l'écran d'accueil.
          Image.asset(
            'assets/images/logo_mountain.png',
            height: 100,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: WSSpacing.lg),
          const Text(
            'WhiteSilence',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: WSColors.slateDark,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: WSSpacing.xs),
          Text(
            'La seule trace, c\'est celle dans la neige.',
            style: WSText.caption.copyWith(
              color: WSColors.stoneGray,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: WSSpacing.xxl),
          const _FeatureRow(
            icon: Icons.lock_open,
            title: 'Sans inscription',
            subtitle: 'Aucun compte, aucun mot de passe à retenir.',
          ),
          const SizedBox(height: WSSpacing.md),
          const _FeatureRow(
            icon: Icons.visibility_off,
            title: 'Sans tracking',
            subtitle:
                'Aucune analytics, aucune publicité, aucun partage de données.',
          ),
          const SizedBox(height: WSSpacing.md),
          const _FeatureRow(
            icon: Icons.code,
            title: 'Open source',
            subtitle: 'Code public sous licence MIT. Vérifiable par tous.',
          ),
        ],
      ),
    );
  }
}

// ─── Page 2 : données locales + GPS ─────────────────────────────────────────

class _Page2LocalData extends StatelessWidget {
  const _Page2LocalData();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WSSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(WSSpacing.lg),
            decoration: BoxDecoration(
              color: WSColors.powderGreen.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.phone_iphone,
              size: 64,
              color: WSColors.powderGreen,
            ),
          ),
          const SizedBox(height: WSSpacing.xl),
          const Text(
            'Tes données restent\nsur ton téléphone',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: WSColors.slateDark,
              height: 1.25,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: WSSpacing.lg),
          Text(
            'Tes sorties, tes observations, tes préférences : '
            'tout est stocké localement. Nous n\'avons pas accès à tes '
            'données et tu peux désinstaller à tout moment sans laisser de trace.',
            style: WSText.body.copyWith(color: WSColors.stoneGray),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: WSSpacing.xl),
          Container(
            padding: const EdgeInsets.all(WSSpacing.md),
            decoration: BoxDecoration(
              color: WSColors.glacierBlue.withOpacity(0.08),
              borderRadius: BorderRadius.circular(WSRadius.md),
              border: Border.all(
                color: WSColors.glacierBlue.withOpacity(0.3),
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on,
                    color: WSColors.glacierBlue, size: 24),
                const SizedBox(width: WSSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Position GPS',
                        style: WSText.body
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Pour les isochrones et la position sur la carte. '
                        'Demandée au lancement de l\'app.',
                        style: WSText.micro
                            .copyWith(color: WSColors.stoneGray),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Page 3 : modules vocaux ────────────────────────────────────────────────

class _Page3Voice extends StatelessWidget {
  const _Page3Voice();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WSSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(WSSpacing.lg),
            decoration: BoxDecoration(
              color: WSColors.glacierBlue.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.mic,
              size: 64,
              color: WSColors.glacierBlue,
            ),
          ),
          const SizedBox(height: WSSpacing.xl),
          const Text(
            'Tout est pensé\npour le terrain',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: WSColors.slateDark,
              height: 1.25,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: WSSpacing.lg),
          Text(
            'Mode gants permanent, observations vocales avec mot-clé '
            '« Hey Snowy », fonctionne hors-ligne avec les tuiles topo '
            'téléchargées. Pensé par et pour des skieurs de rando.',
            style: WSText.body.copyWith(color: WSColors.stoneGray),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: WSSpacing.xl),
          Container(
            padding: const EdgeInsets.all(WSSpacing.md),
            decoration: BoxDecoration(
              color: WSColors.glacierMid.withOpacity(0.2),
              borderRadius: BorderRadius.circular(WSRadius.md),
              border: Border.all(
                color: WSColors.glacierMid,
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.mic_none,
                    color: WSColors.slateDark, size: 24),
                const SizedBox(width: WSSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Micro (optionnel)',
                        style: WSText.body
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Demandé uniquement à la première utilisation '
                        'd\'une observation vocale.',
                        style: WSText.micro
                            .copyWith(color: WSColors.stoneGray),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Helper : une ligne feature (icône + titre + sous-titre) ────────────────

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: WSColors.glacierBlue.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 22, color: WSColors.glacierBlue),
        ),
        const SizedBox(width: WSSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: WSText.body
                      .copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: WSText.micro
                      .copyWith(color: WSColors.stoneGray, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}
