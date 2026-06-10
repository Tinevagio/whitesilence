// lib/shared/settings/routing_zones_screen.dart
//
// Gestion des zones de routage offline (.wsr).
// Calque exact de ZonesScreen (HGT) — même structure, même UX.

import 'package:flutter/material.dart';

import '../../core/routing/routing_tile_downloader.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';

class RoutingZonesScreen extends StatefulWidget {
  const RoutingZonesScreen({super.key});

  @override
  State<RoutingZonesScreen> createState() => _RoutingZonesScreenState();
}

class _RoutingZonesScreenState extends State<RoutingZonesScreen> {
  // zone.id → true/false
  final Map<String, bool> _installed = {};
  final Map<String, DownloadProgress> _progress = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadInstalled();
  }

  Future<void> _loadInstalled() async {
    setState(() => _loading = true);
    for (final zone in RoutingZone.alpineZones) {
      _installed[zone.id] = await RoutingTileDownloader.isInstalled(zone);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _download(RoutingZone zone) async {
    setState(() => _progress[zone.id] =
        const DownloadProgress(status: DownloadStatus.downloading));

    await RoutingTileDownloader.downloadZone(
      zone,
      onProgress: (p) {
        if (mounted) setState(() => _progress[zone.id] = p);
      },
    );

    await _loadInstalled();
    if (mounted) setState(() => _progress.remove(zone.id));
  }

  Future<void> _delete(RoutingZone zone) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: WSColors.snowWhite,
        title: Text('Supprimer ${zone.name} ?'),
        content: const Text(
          'Les données de routage seront supprimées du stockage.\n'
          'Le calcul d\'itinéraire ne fonctionnera plus dans cette zone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: WSColors.avalancheRed,
            ),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await RoutingTileDownloader.deleteZone(zone);
      await _loadInstalled();
    }
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: WSColors.snowWhite,
        title: const Text('À propos des zones de routage'),
        content: const Text(
          'Les données de routage permettent de calculer un itinéraire qui '
          'suit les sentiers, GR et pistes de ski de rando — entièrement '
          'hors-ligne, sans GPS réseau.\n\n'
          'Chaque fichier est généré depuis OpenStreetMap et couvre environ '
          '100×100 km. La taille varie selon la densité de chemins de la zone '
          '(10–30 MB).\n\n'
          'Télécharge les zones de tes sorties habituelles sur WiFi. Une fois '
          'installées, elles fonctionnent sans aucune connexion.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Compris'),
          ),
        ],
      ),
    );
  }

  int get _installedCount => _installed.values.where((v) => v).length;
  double get _installedMb => RoutingZone.alpineZones
      .where((z) => _installed[z.id] == true)
      .fold(0.0, (sum, z) => sum + z.sizeMb);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Zones de routage'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline, size: 20),
            onPressed: _showHelp,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Bandeau info
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(WSSpacing.lg),
                  padding: const EdgeInsets.all(WSSpacing.lg),
                  decoration: BoxDecoration(
                    color: WSColors.glacierBlueBg,
                    borderRadius: BorderRadius.circular(WSRadius.lg),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.route_outlined,
                          color: WSColors.glacierBlue, size: 20),
                      const SizedBox(width: WSSpacing.md),
                      Expanded(
                        child: Text(
                          'Télécharge les zones avant ta sortie pour calculer '
                          'des itinéraires qui suivent les sentiers, '
                          'entièrement hors-ligne.',
                          style:
                              WSText.body.copyWith(color: WSColors.glacierBlue),
                        ),
                      ),
                    ],
                  ),
                ),

                // Liste des zones
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: WSSpacing.lg),
                    itemCount: RoutingZone.alpineZones.length,
                    itemBuilder: (_, i) {
                      final zone = RoutingZone.alpineZones[i];
                      return _ZoneTile(
                        zone: zone,
                        installed: _installed[zone.id] ?? false,
                        progress: _progress[zone.id],
                        onDownload: () => _download(zone),
                        onDelete: () => _delete(zone),
                      );
                    },
                  ),
                ),

                // Footer stockage
                Padding(
                  padding: const EdgeInsets.all(WSSpacing.lg),
                  child: Text(
                    '$_installedCount zone(s) installée(s)  ·  '
                    '~${_installedMb.toStringAsFixed(0)} MB utilisés',
                    style: WSText.caption,
                  ),
                ),
              ],
            ),
    );
  }
}

// ── Tuile de zone ─────────────────────────────────────────────────────────────

class _ZoneTile extends StatelessWidget {
  final RoutingZone zone;
  final bool installed;
  final DownloadProgress? progress;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  const _ZoneTile({
    required this.zone,
    required this.installed,
    required this.progress,
    required this.onDownload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDownloading = progress != null &&
        progress!.status == DownloadStatus.downloading;
    final isError = progress?.status == DownloadStatus.error;

    return Container(
      margin: const EdgeInsets.only(bottom: WSSpacing.sm),
      padding: const EdgeInsets.all(WSSpacing.lg),
      decoration: BoxDecoration(
        color: WSColors.snowWhite,
        borderRadius: BorderRadius.circular(WSRadius.lg),
        border: Border.all(color: WSColors.glacierMid, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête : icône + nom + taille
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: installed
                      ? WSColors.powderGreenBg
                      : WSColors.glacierLight,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  installed ? Icons.check_rounded : Icons.route_outlined,
                  size: 18,
                  color:
                      installed ? WSColors.powderGreen : WSColors.stoneGray,
                ),
              ),
              const SizedBox(width: WSSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(zone.name,
                        style: WSText.body
                            .copyWith(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text(zone.description, style: WSText.caption),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: WSSpacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: WSColors.glacierLight,
                  borderRadius: BorderRadius.circular(WSRadius.sm),
                ),
                child: Text(
                  '~${zone.sizeMb.toStringAsFixed(0)} MB',
                  style: WSText.micro,
                ),
              ),
            ],
          ),

          // Barre de progression
          if (isDownloading) ...[
            const SizedBox(height: WSSpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress!.progress,
                minHeight: 4,
                backgroundColor: WSColors.glacierLight,
                valueColor:
                    const AlwaysStoppedAnimation(WSColors.glacierBlue),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Téléchargement… ${(progress!.progress * 100).toStringAsFixed(0)}%',
              style: WSText.micro,
            ),
          ],

          // Erreur
          if (isError) ...[
            const SizedBox(height: WSSpacing.sm),
            Row(children: [
              const Icon(Icons.error_outline,
                  size: 14, color: WSColors.avalancheRed),
              const SizedBox(width: 4),
              Expanded(
                  child: Text(progress!.error ?? 'Erreur',
                      style: WSText.micro
                          .copyWith(color: WSColors.avalancheRed))),
            ]),
          ],

          // Actions
          if (!isDownloading) ...[
            const SizedBox(height: WSSpacing.md),
            Row(
              children: [
                if (installed) ...[
                  OutlinedButton(
                    onPressed: onDelete,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: WSColors.avalancheRed,
                      side: const BorderSide(
                          color: WSColors.avalancheRed, width: 0.5),
                    ),
                    child: const Text('Supprimer'),
                  ),
                  const SizedBox(width: WSSpacing.sm),
                  const Text('Installé',
                      style: TextStyle(
                          color: WSColors.powderGreen,
                          fontWeight: FontWeight.w500,
                          fontSize: 12)),
                ] else
                  FilledButton.icon(
                    onPressed: onDownload,
                    icon: const Icon(Icons.download_outlined, size: 16),
                    label: const Text('Télécharger'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
