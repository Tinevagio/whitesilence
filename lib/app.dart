import 'package:flutter/material.dart';

import 'core/map/map_module_overlay.dart';
import 'core/map/map_screen.dart';
import 'core/module_navigator.dart';
import 'core/module_registry.dart';
import 'core/theme/colors.dart';
import 'core/theme/spacing.dart';
import 'shared/settings/settings_screen.dart';

/// Shell principal de WhiteSilence.
///
/// Architecture :
///   - Une UNIQUE MapScreen au centre
///   - Une bottom bar qui sélectionne le module actif (Temps, Neige, ...)
///   - Un bouton réglages en AppBar
///
/// Les modules désactivés disparaissent de la bottom bar.
class WSShell extends StatefulWidget {
  /// Overlays fournis au démarrage (un par module implémenté).
  /// Cette liste grandit phase après phase.
  final List<MapModuleOverlay> overlays;

  const WSShell({super.key, required this.overlays});

  @override
  State<WSShell> createState() => _WSShellState();
}

class _WSShellState extends State<WSShell> {
  final ModuleRegistry _registry = ModuleRegistry();
  final ModuleNavigator _navigator = ModuleNavigator();
  ModuleId? _active;

  @override
  void initState() {
    super.initState();
    _registry.addListener(_onRegistryChanged);
    _navigator.requestedModule.addListener(_onNavRequest);
    _pickFirstAvailable();
  }

  @override
  void dispose() {
    _registry.removeListener(_onRegistryChanged);
    _navigator.requestedModule.removeListener(_onNavRequest);
    super.dispose();
  }

  void _onRegistryChanged() {
    // Si le module actif vient d'être désactivé → basculer sur un autre.
    if (_active == null || !_registry.isEnabled(_active!)) {
      _pickFirstAvailable();
      return; // setState déjà fait dans _pickFirstAvailable
    }
    // Sinon, le module actif reste valide, mais d'autres modules ont pu
    // être (ré)activés/désactivés → on doit rebuild pour mettre à jour la
    // bottom bar et la liste des overlays.
    setState(() {});
  }

  /// Réponse à une demande cross-module : un module (typiquement Idées) a
  /// demandé via ModuleNavigator de basculer vers un autre. On vérifie que
  /// le module cible est bien activé puis on switch.
  void _onNavRequest() {
    final target = _navigator.requestedModule.value;
    if (target == null) return;
    if (!_registry.isEnabled(target)) return;
    setState(() => _active = target);
  }

  void _pickFirstAvailable() {
    final available = ModuleRegistry.catalog
        .where((m) => _registry.isEnabled(m.id))
        .toList();
    setState(() {
      _active = available.isEmpty ? null : available.first.id;
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeOverlays = widget.overlays
        .where((o) => _registry.isEnabled(o.id))
        .toList();
    final visibleModules = ModuleRegistry.catalog
        .where((m) => _registry.isEnabled(m.id))
        .toList();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'WhiteSilence',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: WSColors.slateDark,
            letterSpacing: 0.5,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune, size: 20, color: WSColors.slateDark),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: _active == null
          ? const _NoModuleEnabled()
          : WSMapScreen(
              activeModule: _active!,
              overlays: activeOverlays,
              onModuleChanged: (id) => setState(() => _active = id),
            ),
      bottomNavigationBar: visibleModules.isEmpty
          ? null
          : _buildBottomBar(visibleModules),
    );
  }

  Widget _buildBottomBar(List<ModuleInfo> visible) {
    final idx = visible.indexWhere((m) => m.id == _active);
    // SafeArea garantit que la bottom bar ne mord pas sur la barre système
    // (notamment la home indicator des téléphones sans bouton).
    return SafeArea(
      top: false,
      child: SizedBox(
        // Hauteur fixe XL pour cible tactile généreuse au gant.
        height: WSTouch.bottomBarHeight,
        child: BottomNavigationBar(
          currentIndex: idx < 0 ? 0 : idx,
          onTap: (i) => setState(() => _active = visible[i].id),
          // Sécurité : on force iconSize même si déjà dans le thème, parce
          // que des versions de Flutter peuvent ignorer le thème dans certains
          // contextes (bug connu).
          iconSize: WSTouch.bottomBarIcon,
          items: [
            for (final m in visible)
              BottomNavigationBarItem(
                icon: Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Icon(m.icon),
                ),
                label: m.label,
              ),
          ],
        ),
      ),
    );
  }
}

class _NoModuleEnabled extends StatelessWidget {
  const _NoModuleEnabled();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.layers_clear_outlined,
                size: 48, color: WSColors.stoneGray),
            const SizedBox(height: 16),
            const Text(
              'Tous les modules sont désactivés.',
              style: TextStyle(color: WSColors.stoneGray),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
              child: const Text('Ouvrir les réglages'),
            ),
          ],
        ),
      ),
    );
  }
}