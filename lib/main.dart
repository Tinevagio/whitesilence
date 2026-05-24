import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app.dart';
import 'core/gps/gps_service.dart';
import 'core/module_registry.dart';
import 'core/onboarding/onboarding_screen.dart';
import 'core/onboarding/onboarding_service.dart';
import 'core/theme/theme.dart';
import 'modules/conditions/conditions_overlay.dart';
import 'modules/ideas/ideas_overlay.dart';
import 'modules/snow/services/supabase_service.dart';
import 'modules/snow/snow_overlay.dart';
import 'modules/time/time_controller.dart';
import 'modules/time/time_overlay.dart';
import 'shared/settings/user_profile.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Charge le .env (clés API). Si absent, on continue : chaque service
  // gérera l'absence de sa clé proprement.
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    debugPrint('[main] .env absent ou illisible : $e — les modules en ligne'
               ' seront désactivés');
  }

  // Status bar transparente, icônes sombres (fond clair de l'app)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // Initialise les singletons partagés AVANT runApp
  await Future.wait([
    UserProfile().load(),
    ModuleRegistry().load(),
    SupabaseService.initialize(), // no-op si clés absentes
  ]);

  // Démarre le GPS — partagé entre tous les modules.
  GpsService().start().catchError((e) {
    debugPrint('[main] GPS start failed: $e');
  });

  // Démarre le contrôleur du module Temps (branche le calibrateur sur le GPS).
  // Le SnowController.start() est appelé paresseusement par son action panel
  // (il a besoin de permission micro qu'on ne demande qu'au premier usage).
  TimeController().start();

  runApp(const WhiteSilenceApp());
}

class WhiteSilenceApp extends StatelessWidget {
  const WhiteSilenceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WhiteSilence',
      debugShowCheckedModeBanner: false,
      theme: WSTheme.light(),
      // Localization Material/Cupertino/Widgets pour avoir DatePicker, etc.
      // en français. Sans ces delegates, le DatePicker plante avec
      // "No MaterialLocalizations found".
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('fr', 'FR'),
        Locale('en', 'US'),
      ],
      locale: const Locale('fr', 'FR'),
      home: const _AppEntrypoint(),
    );
  }
}

/// Décide entre l'onboarding et l'app principale au démarrage.
/// - Au boot : lit `OnboardingService.hasSeenCurrent()` (rapide, prefs).
/// - Si pas vu : montre OnboardingScreen, puis bascule vers WSShell.
/// - Si vu : démarre directement sur WSShell.
class _AppEntrypoint extends StatefulWidget {
  const _AppEntrypoint();
  @override
  State<_AppEntrypoint> createState() => _AppEntrypointState();
}

class _AppEntrypointState extends State<_AppEntrypoint> {
  /// null = on est encore en train de vérifier les prefs (très court)
  /// true = onboarding déjà vu, on montre l'app
  /// false = onboarding pas encore vu, on le montre
  bool? _onboardingDone;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final seen = await OnboardingService().hasSeenCurrent();
    if (mounted) setState(() => _onboardingDone = seen);
  }

  @override
  Widget build(BuildContext context) {
    // Pendant la lecture des prefs, on affiche un splash neutre. C'est très
    // court (50-100 ms) et évite un flash de l'app pour rien si on doit
    // bifurquer sur l'onboarding.
    if (_onboardingDone == null) {
      return const Scaffold(body: ColoredBox(color: Colors.white));
    }
    if (_onboardingDone == false) {
      return OnboardingScreen(
        onFinished: () => setState(() => _onboardingDone = true),
      );
    }
    return WSShell(overlays: [
      TimeModuleOverlay(),
      SnowModuleOverlay(),
      ConditionsModuleOverlay(),
      IdeasModuleOverlay(),
    ]);
  }
}
