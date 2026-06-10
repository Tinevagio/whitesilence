import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/links.dart';
import '../../core/map/cached_tile_provider.dart';
import '../../core/module_registry.dart';
import '../../core/onboarding/onboarding_service.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../about/credits_screen.dart';
import '../about/privacy_screen.dart';
import '../manifesto/manifesto_screen.dart';
import 'user_profile.dart';
import 'offline_zones_screen.dart';
//import 'zones_screen.dart';
//import 'routing_zones_screen.dart';



class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _registry = ModuleRegistry();
  final _profile = UserProfile();

  @override
  void initState() {
    super.initState();
    _registry.addListener(_refresh);
    _profile.addListener(_refresh);
  }

  @override
  void dispose() {
    _registry.removeListener(_refresh);
    _profile.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: WSSpacing.lg,
          vertical: WSSpacing.md,
        ),
        children: [
          _section('Profil'),
          _ActivitySelector(profile: _profile),
          const SizedBox(height: WSSpacing.sm),
          _LevelSelector(profile: _profile),

          const SizedBox(height: WSSpacing.xl),
          _section('Modules'),
          for (final m in ModuleRegistry.catalog)
            _ModuleTile(info: m, registry: _registry),

          const SizedBox(height: WSSpacing.xl),
          _section('Cartes hors-ligne'),
          /*
		  _LinkTile(
            icon: Icons.terrain_outlined,
            label: 'Zones topographiques',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ZonesScreen()),
            ),
          ),*/
		  _LinkTile(
			  icon: Icons.layers_outlined,
			  label: 'Zones hors-ligne',
			  onTap: () => Navigator.of(context).push(
				MaterialPageRoute(builder: (_) => const OfflineZonesScreen()),
			  ),
		  ),
          _LinkTile(
            icon: Icons.map_outlined,
            label: 'Cache des tuiles de carte',
            onTap: () => showModalBottomSheet(
              context: context,
              backgroundColor: Colors.transparent,
              builder: (_) => const _TileCacheSheet(),
            ),
          ),

          const SizedBox(height: WSSpacing.xl),
          _section('Soutenir'),
          _LinkTile(
            icon: Icons.coffee_outlined,
            label: 'Offrir un café (Ko-fi)',
            onTap: () => launchUrl(
              Uri.parse(kKofiUrl),
              mode: LaunchMode.externalApplication,
            ),
          ),
          _LinkTile(
            icon: Icons.favorite_outline,
            label: 'Sponsoriser sur GitHub',
            onTap: () => launchUrl(
              Uri.parse(kGitHubSponsorsUrl),
              mode: LaunchMode.externalApplication,
            ),
          ),

          const SizedBox(height: WSSpacing.xl),
          _section('À propos'),
          _LinkTile(
            icon: Icons.eco_outlined,
            label: 'Le manifeste WhiteSilence',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ManifestoScreen()),
            ),
          ),
          _LinkTile(
            icon: Icons.layers_outlined,
            label: 'Crédits & sources',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CreditsScreen()),
            ),
          ),
          _LinkTile(
            icon: Icons.privacy_tip_outlined,
            label: 'Confidentialité',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PrivacyScreen()),
            ),
          ),
          _LinkTile(
            icon: Icons.code,
            label: 'Code source (GitHub)',
            onTap: () => launchUrl(
              Uri.parse(kGitHubRepoUrl),
              mode: LaunchMode.externalApplication,
            ),
          ),
          _LinkTile(
            icon: Icons.replay_outlined,
            label: 'Revoir l\'écran d\'accueil',
            onTap: () async {
              await OnboardingService().reset();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('L\'écran d\'accueil s\'affichera au prochain démarrage.'),
                behavior: SnackBarBehavior.floating,
              ));
            },
          ),
		  
          const SizedBox(height: WSSpacing.xxl),
          const Center(
            child: Text(
              'WhiteSilence · v0.1.0',
              style: WSText.caption,
            ),
          ),
          const SizedBox(height: WSSpacing.xl),
        ],
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(
        top: WSSpacing.md,
        bottom: WSSpacing.sm,
      ),
      child: Text(
        title.toUpperCase(),
        style: WSText.micro.copyWith(color: WSColors.stoneGray),
      ),
    );
  }
}

class _ActivitySelector extends StatelessWidget {
  final UserProfile profile;
  const _ActivitySelector({required this.profile});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Activité', style: WSText.caption),
          const SizedBox(height: WSSpacing.sm),
          SegmentedButton<Activity>(
            segments: const [
              ButtonSegment(value: Activity.hiking, label: Text('Rando')),
              ButtonSegment(value: Activity.skiTouring, label: Text('Ski rando')),
              ButtonSegment(value: Activity.trailRunning, label: Text('Trail')),
            ],
            selected: {profile.activity},
            onSelectionChanged: (s) => profile.setActivity(s.first),
          ),
        ],
      ),
    );
  }
}

class _LevelSelector extends StatelessWidget {
  final UserProfile profile;
  const _LevelSelector({required this.profile});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Niveau', style: WSText.caption),
          const SizedBox(height: WSSpacing.sm),
          SegmentedButton<Level>(
            segments: const [
              ButtonSegment(value: Level.beginner, label: Text('Débutant')),
              ButtonSegment(value: Level.trained, label: Text('Entraîné')),
              ButtonSegment(value: Level.warrior, label: Text('Warrior')),
            ],
            selected: {profile.level},
            onSelectionChanged: (s) => profile.setLevel(s.first),
          ),
        ],
      ),
    );
  }
}

class _ModuleTile extends StatelessWidget {
  final ModuleInfo info;
  final ModuleRegistry registry;
  const _ModuleTile({required this.info, required this.registry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: WSSpacing.sm),
      child: _Card(
        child: Row(
          children: [
            Icon(info.icon, size: 22, color: WSColors.glacierBlue),
            const SizedBox(width: WSSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(info.label, style: WSText.body),
                  const SizedBox(height: 2),
                  Text(info.description, style: WSText.caption),
                ],
              ),
            ),
            Switch(
              value: registry.isEnabled(info.id),
              onChanged: (v) => registry.setEnabled(info.id, v),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _LinkTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: WSSpacing.sm),
      child: _Card(
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, size: 22, color: WSColors.stoneGray),
            const SizedBox(width: WSSpacing.md),
            Expanded(child: Text(label, style: WSText.body)),
            const Icon(Icons.chevron_right, size: 18, color: WSColors.stoneGray),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _Card({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WSColors.snowWhite,
      borderRadius: BorderRadius.circular(WSRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(WSRadius.lg),
        child: Container(
          padding: const EdgeInsets.all(WSSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(WSRadius.lg),
            border: Border.all(color: WSColors.glacierMid, width: 0.5),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Bottom sheet affichant la taille du cache de tuiles topo + bouton pour
/// le vider. Recalcul de la taille à chaque ouverture (pas de cache de la
/// taille — c'est rapide en pratique sauf cache énorme).
class _TileCacheSheet extends StatefulWidget {
  const _TileCacheSheet();

  @override
  State<_TileCacheSheet> createState() => _TileCacheSheetState();
}

class _TileCacheSheetState extends State<_TileCacheSheet> {
  int? _sizeBytes;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _sizeBytes = null);
    final s = await CachedTileProvider.cacheSizeBytes();
    if (mounted) setState(() => _sizeBytes = s);
  }

  Future<void> _clear() async {
    setState(() => _clearing = true);
    await CachedTileProvider.clearCache();
    if (!mounted) return;
    setState(() => _clearing = false);
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Cache des tuiles vidé'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: WSColors.snowWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(WSRadius.xl)),
      ),
      padding: const EdgeInsets.fromLTRB(
        WSSpacing.xl, WSSpacing.lg, WSSpacing.xl, WSSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
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
          const Text('Cache des tuiles', style: WSText.title),
          const SizedBox(height: WSSpacing.sm),
          const Text(
            'Les tuiles de carte que tu as vues sont sauvegardées localement et '
            'restent disponibles sans connexion.',
            style: WSText.caption,
          ),
          const SizedBox(height: WSSpacing.lg),
          Container(
            padding: const EdgeInsets.all(WSSpacing.md),
            decoration: BoxDecoration(
              color: WSColors.glacierLight,
              borderRadius: BorderRadius.circular(WSRadius.md),
            ),
            child: Row(
              children: [
                const Icon(Icons.sd_storage_outlined,
                    size: 18, color: WSColors.stoneGray),
                const SizedBox(width: WSSpacing.md),
                const Expanded(
                  child: Text('Taille du cache', style: WSText.body),
                ),
                if (_sizeBytes == null)
                  const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      valueColor: AlwaysStoppedAnimation(WSColors.glacierBlue),
                    ),
                  )
                else
                  Text(
                    _formatBytes(_sizeBytes!),
                    style: WSText.body.copyWith(fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
          const SizedBox(height: WSSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: (_clearing || _sizeBytes == 0) ? null : _clear,
              icon: _clearing
                  ? const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor:
                            AlwaysStoppedAnimation(WSColors.avalancheRed),
                      ),
                    )
                  : const Icon(Icons.delete_outline, size: 18),
              label: Text(_clearing
                  ? 'Suppression…'
                  : _sizeBytes == 0
                      ? 'Cache vide'
                      : 'Vider le cache'),
              style: OutlinedButton.styleFrom(
                foregroundColor: WSColors.avalancheRed,
                side: const BorderSide(color: WSColors.avalancheRed, width: 0.5),
                padding: const EdgeInsets.symmetric(vertical: WSSpacing.md),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
