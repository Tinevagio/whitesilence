// lib/shared/settings/zones_screen.dart
//
// Gestion des zones topographiques HGT.
// Migré depuis TimeToGo, restylé WhiteSilence.
// Devient partagé : tous les modules qui ont besoin d'altitude
// (time, snow, avalanche) bénéficient des HGT installés.

import 'package:flutter/material.dart';

import '../../core/elevation/hgt_downloader.dart';
import '../../core/elevation/hgt_provider.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';

class ZonesScreen extends StatefulWidget {
  const ZonesScreen({super.key});

  @override
  State<ZonesScreen> createState() => _ZonesScreenState();
}

class _ZonesScreenState extends State<ZonesScreen> {
  List<String> _installed = [];
  final Map<String, DownloadProgress> _progress = {};

  @override
  void initState() {
    super.initState();
    _loadInstalled();
  }

  Future<void> _loadInstalled() async {
    final tiles = await HgtElevationProvider.installedTiles();
    if (mounted) setState(() => _installed = tiles);
  }

  Future<void> _download(HgtMassif massif) async {
    setState(() => _progress[massif.tile] =
        const DownloadProgress(status: DownloadStatus.downloading));

    await HgtDownloader.downloadTile(
      massif.tile,
      onProgress: (p) {
        if (mounted) setState(() => _progress[massif.tile] = p);
      },
    );

    HgtElevationProvider.invalidateCache(massif.tile);
    await _loadInstalled();
    if (mounted) setState(() => _progress.remove(massif.tile));
  }

  Future<void> _delete(HgtMassif massif) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: WSColors.snowWhite,
        title: Text('Supprimer ${massif.name} ?'),
        content: const Text(
          'Le fichier topographique sera supprimé du stockage.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await HgtElevationProvider.deleteTile(massif.tile);
      await _loadInstalled();
    }
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: WSColors.snowWhite,
        title: const Text('À propos des zones'),
        content: const Text(
          'Les fichiers topographiques (HGT SRTM1) donnent l\'altitude avec '
          'une précision de 30m — bien meilleure que le mode en ligne (~400m).\n\n'
          'Chaque fichier couvre environ 100×100 km et pèse ~25 MB une fois '
          'installé (~12 MB à télécharger).\n\n'
          'Télécharge les zones de tes sorties habituelles sur WiFi avant de '
          'partir. Une fois installées, elles fonctionnent entièrement hors-ligne.',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Zones topographiques'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline, size: 20),
            onPressed: _showHelp,
          ),
        ],
      ),
      body: Column(
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
                const Icon(Icons.terrain_outlined,
                    color: WSColors.glacierBlue, size: 20),
                const SizedBox(width: WSSpacing.md),
                Expanded(
                  child: Text(
                    'Télécharge les zones avant ta sortie pour des isochrones '
                    'précises à 30m, fonctionnant entièrement hors-ligne.',
                    style: WSText.body.copyWith(color: WSColors.glacierBlue),
                  ),
                ),
              ],
            ),
          ),

          // Liste des massifs
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: WSSpacing.lg),
              itemCount: HgtMassif.alpinesMassifs.length,
              itemBuilder: (_, i) {
                final massif = HgtMassif.alpinesMassifs[i];
                return _MassifTile(
                  massif:    massif,
                  installed: _installed.contains(massif.tile),
                  progress:  _progress[massif.tile],
                  onDownload: () => _download(massif),
                  onDelete:   () => _delete(massif),
                );
              },
            ),
          ),

          // Footer stockage
          Padding(
            padding: const EdgeInsets.all(WSSpacing.lg),
            child: Text(
              '${_installed.length} zone(s) installée(s)  ·  '
              '~${(_installed.length * 25).toStringAsFixed(0)} MB utilisés',
              style: WSText.caption,
            ),
          ),
        ],
      ),
    );
  }
}

class _MassifTile extends StatelessWidget {
  final HgtMassif massif;
  final bool installed;
  final DownloadProgress? progress;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  const _MassifTile({
    required this.massif,
    required this.installed,
    required this.progress,
    required this.onDownload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isLoading = progress != null
        && progress!.status != DownloadStatus.done
        && progress!.status != DownloadStatus.error;
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
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: installed ? WSColors.powderGreenBg : WSColors.glacierLight,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  installed ? Icons.check_rounded : Icons.download_outlined,
                  size: 18,
                  color: installed ? WSColors.powderGreen : WSColors.stoneGray,
                ),
              ),
              const SizedBox(width: WSSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(massif.name, style: WSText.body.copyWith(
                        fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text(massif.description, style: WSText.caption),
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
                child: const Text('~12 MB', style: WSText.micro),
              ),
            ],
          ),

          if (isLoading) ...[
            const SizedBox(height: WSSpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress!.progress,
                minHeight: 4,
                backgroundColor: WSColors.glacierLight,
                valueColor: const AlwaysStoppedAnimation(WSColors.glacierBlue),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              progress!.status == DownloadStatus.extracting
                  ? 'Extraction…'
                  : 'Téléchargement… ${(progress!.progress * 100).toStringAsFixed(0)}%',
              style: WSText.micro,
            ),
          ],

          if (isError) ...[
            const SizedBox(height: WSSpacing.sm),
            Row(children: [
              const Icon(Icons.error_outline, size: 14, color: WSColors.avalancheRed),
              const SizedBox(width: 4),
              Expanded(child: Text(progress!.error ?? 'Erreur',
                style: WSText.micro.copyWith(color: WSColors.avalancheRed))),
            ]),
          ],

          if (!isLoading) ...[
            const SizedBox(height: WSSpacing.md),
            Row(
              children: [
                if (installed) ...[
                  OutlinedButton(
                    onPressed: onDelete,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: WSColors.avalancheRed,
                      side: const BorderSide(color: WSColors.avalancheRed, width: 0.5),
                    ),
                    child: const Text('Supprimer'),
                  ),
                  const SizedBox(width: WSSpacing.sm),
                  const Text('Installé', style: TextStyle(
                      color: WSColors.powderGreen,
                      fontWeight: FontWeight.w500,
                      fontSize: 12)),
                ] else
                  FilledButton.icon(
                    onPressed: progress != null ? null : onDownload,
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
