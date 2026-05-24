import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Identifiant unique d'un module WhiteSilence.
enum ModuleId {
  time,       // ex-GhostTime (Munter + isochrones)
  snow,       // Observations nivologiques (vocales ou rapides) — mes obs + communauté
  conditions, // ex-Névé (conditions + BERA + avalanche, en WebView)
  ideas,      // ex-Ski-touring-live (recommandations d'itinéraires, WebView Streamlit)
  community,  // ⚠️ Déprécié : fusionné dans `snow` depuis la v0.5. Conservé pour
              // compat ascendante (SharedPreferences existantes). Ne plus utiliser.
}

/// Métadonnées d'un module : nom affiché, icône, état actif/inactif.
class ModuleInfo {
  final ModuleId id;
  final String label;
  final IconData icon;
  final String description;
  final bool implemented;

  const ModuleInfo({
    required this.id,
    required this.label,
    required this.icon,
    required this.description,
    this.implemented = false,
  });
}

/// Catalogue + état des modules. La bottom bar et l'écran réglages
/// s'abonnent à ce registre pour savoir quoi afficher.
class ModuleRegistry extends ChangeNotifier {
  static final ModuleRegistry _instance = ModuleRegistry._();
  factory ModuleRegistry() => _instance;
  ModuleRegistry._();

  /// Toujours dans cet ordre dans la bottom bar.
  static const List<ModuleInfo> catalog = [
    ModuleInfo(
      id: ModuleId.time,
      label: 'Temps',
      icon: Icons.schedule_outlined,
      description: 'Estimation de temps de parcours (Munter) et isochrones.',
    ),
    ModuleInfo(
      id: ModuleId.snow,
      label: 'Obs',
      icon: Icons.ac_unit_outlined,
      description:
          'Observations nivologiques : tes obs et celles de la communauté.',
    ),
    ModuleInfo(
      id: ModuleId.conditions,
      label: 'Conditions',
      icon: Icons.cloud_outlined,
      description:
          'Conditions de neige + BERA + zones d\'avalanche (vue web Névé).',
    ),
    ModuleInfo(
      id: ModuleId.ideas,
      label: 'Idées',
      icon: Icons.lightbulb_outline,
      description:
          'Suggestions d\'itinéraires selon les conditions et ton niveau.',
    ),
  ];

  final Map<ModuleId, bool> _enabled = {
    for (final m in catalog) m.id: true,
  };

  bool isEnabled(ModuleId id) => _enabled[id] ?? false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    for (final m in catalog) {
      _enabled[m.id] = prefs.getBool('module.${m.id.name}') ?? true;
    }
    notifyListeners();
  }

  Future<void> setEnabled(ModuleId id, bool value) async {
    _enabled[id] = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('module.${id.name}', value);
    notifyListeners();
  }
}
