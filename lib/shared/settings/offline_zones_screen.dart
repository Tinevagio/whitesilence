// lib/shared/settings/offline_zones_screen.dart
//
// Écran unifié de gestion des données hors-ligne.
// Remplace ZonesScreen (HGT seul) et RoutingZonesScreen (WSR seul).
//
// UX : une carte des Alpes + Pyrénées avec un quadrillage 1°×1°.
// Chaque case est colorée selon l'état d'installation de ses deux couches
// de données (altitude HGT + routage WSR). Un tap ouvre un bottom sheet
// avec les détails et les boutons télécharger/supprimer.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/map/cached_tile_provider.dart';
import '../../core/offline/offline_zone_manager.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';

// ── Région affichée ───────────────────────────────────────────────────────────
// Couvre Alpes françaises + Pyrénées + Jura/Vosges.
const double _latMin = 42.0, _latMax = 48.0;
const double _lngMin = -2.0, _lngMax = 10.0;

class OfflineZonesScreen extends StatefulWidget {
  const OfflineZonesScreen({super.key});

  @override
  State<OfflineZonesScreen> createState() => _OfflineZonesScreenState();
}

class _OfflineZonesScreenState extends State<OfflineZonesScreen> {
  final _manager = OfflineZoneManager();

  @override
  void initState() {
    super.initState();
    _manager.addListener(_refresh);
    _manager.load();
  }

  @override
  void dispose() {
    _manager.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  // ── Couleur d'une case ────────────────────────────────────────────────────

  Color _cellColor(String key) {
    final dl = _manager.downloadOf(key);
    if (dl != null && dl.status == ZoneDownloadStatus.downloading) {
      return WSColors.glacierBlue.withOpacity(0.45);
    }
    final s = _manager.stateOf(key);
    if (s.hgtInstalled && s.wsrInstalled) {
      return WSColors.powderGreen.withOpacity(0.45);   // tout installé
    }
    if (s.hgtInstalled) {
      return WSColors.glacierBlue.withOpacity(0.30);   // HGT seulement
    }
    if (s.wsrInstalled) {
      return WSColors.sunOrange.withOpacity(0.30);     // WSR seulement
    }
    if (s.wsrAvailable) {
      return WSColors.glacierMid.withOpacity(0.25);    // disponible, non installé
    }
    return Colors.transparent;
  }

  // ── Polygones du quadrillage ──────────────────────────────────────────────

  List<Polygon> _buildGrid() {
    final polygons = <Polygon>[];
    for (var lat = _latMin.toInt(); lat < _latMax.toInt(); lat++) {
      for (var lng = _lngMin.toInt(); lng < _lngMax.toInt(); lng++) {
        final key = OfflineZoneManager.keyFromLatLng(
            lat.toDouble(), lng.toDouble());
        final color = _cellColor(key);
        if (color == Colors.transparent) continue;
        polygons.add(Polygon(
          points: [
            LatLng(lat.toDouble(), lng.toDouble()),
            LatLng(lat.toDouble(), lng + 1.0),
            LatLng(lat + 1.0, lng + 1.0),
            LatLng(lat + 1.0, lng.toDouble()),
          ],
          color: color,
          borderColor: WSColors.glacierBlue.withOpacity(0.4),
          borderStrokeWidth: 0.5,
        ));
      }
    }
    return polygons;
  }

  // Lignes de grille (toutes les cases, même les vides)
  List<Polyline> _buildGridLines() {
    final lines = <Polyline>[];
    const style = Color(0x22607D8B); // bleu-gris discret
    for (var lat = _latMin.toInt(); lat <= _latMax.toInt(); lat++) {
      lines.add(Polyline(
        points: [LatLng(lat.toDouble(), _lngMin), LatLng(lat.toDouble(), _lngMax)],
        color: style, strokeWidth: 0.5,
      ));
    }
    for (var lng = _lngMin.toInt(); lng <= _lngMax.toInt(); lng++) {
      lines.add(Polyline(
        points: [LatLng(_latMin, lng.toDouble()), LatLng(_latMax, lng.toDouble())],
        color: style, strokeWidth: 0.5,
      ));
    }
    return lines;
  }

  // ── Tap sur la carte ──────────────────────────────────────────────────────

  void _onTap(TapPosition _, LatLng latlng) {
    if (latlng.latitude < _latMin || latlng.latitude > _latMax) return;
    if (latlng.longitude < _lngMin || latlng.longitude > _lngMax) return;
    final key = OfflineZoneManager.keyFromLatLng(
        latlng.latitude, latlng.longitude);
    _showTileSheet(key);
  }

  void _showTileSheet(String key) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _TileSheet(
        tileKey: key,
        manager: _manager,
      ),
    );
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Zones hors-ligne'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline, size: 20),
            onPressed: _showHelp,
          ),
        ],
      ),
      body: Column(
        children: [
          // Carte interactive
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: const LatLng(45.0, 6.5),
                initialZoom: 5.5,
                minZoom: 4,
                maxZoom: 8,
                onTap: _onTap,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.opentopomap.org/{z}/{x}/{y}.png',
                  tileProvider: CachedTileProvider(),
                  userAgentPackageName: 'app.whitesilence.whitesilence',
                ),
                if (!_manager.loading) ...[
                  PolylineLayer(polylines: _buildGridLines()),
                  PolygonLayer(polygons: _buildGrid()),
                ],
                if (_manager.loading)
                  const ColoredBox(
                    color: Color(0x33FFFFFF),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
          // Légende
          _Legend(manager: _manager),
        ],
      ),
    );
  }

  void _showHelp() => showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: WSColors.snowWhite,
          title: const Text('Zones hors-ligne'),
          content: const Text(
            'Chaque case représente une zone de 100×100 km.\n\n'
            '🟢 Vert — altitude + itinéraires installés\n'
            '🔵 Bleu — altitude seule installée\n'
            '🟠 Orange — itinéraires seuls installés\n'
            '⬜ Gris — disponible, non installé\n\n'
            'Touche une case pour télécharger ou supprimer ses données. '
            'Télécharge sur WiFi avant ta sortie.',
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

// ── Légende ───────────────────────────────────────────────────────────────────

class _Legend extends StatelessWidget {
  final OfflineZoneManager manager;
  const _Legend({required this.manager});

  @override
  Widget build(BuildContext context) {
    final states = manager.states.values;
    final hgtCount = states.where((s) => s.hgtInstalled).length;
    final wsrCount = states.where((s) => s.wsrInstalled).length;

    return Container(
      color: WSColors.snowWhite,
      padding: const EdgeInsets.symmetric(
          horizontal: WSSpacing.lg, vertical: WSSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _dot(WSColors.powderGreen), const SizedBox(width: 4),
              Text('Complet', style: WSText.micro),
              const SizedBox(width: WSSpacing.md),
              _dot(WSColors.glacierBlue), const SizedBox(width: 4),
              Text('Altitude', style: WSText.micro),
              const SizedBox(width: WSSpacing.md),
              _dot(WSColors.sunOrange), const SizedBox(width: 4),
              Text('Itinéraire', style: WSText.micro),
              const SizedBox(width: WSSpacing.md),
              _dot(WSColors.glacierMid), const SizedBox(width: 4),
              Text('Disponible', style: WSText.micro),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$hgtCount zone(s) altitude · $wsrCount zone(s) itinéraire',
            style: WSText.caption,
          ),
        ],
      ),
    );
  }

  Widget _dot(Color color) => Container(
        width: 10, height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

// ── Bottom sheet d'une tuile ──────────────────────────────────────────────────

class _TileSheet extends StatefulWidget {
  final String tileKey;
  final OfflineZoneManager manager;
  const _TileSheet({required this.tileKey, required this.manager});

  @override
  State<_TileSheet> createState() => _TileSheetState();
}

class _TileSheetState extends State<_TileSheet> {
  late TileState _state;
  ZoneDownloadState? _dl;

  @override
  void initState() {
    super.initState();
    _state = widget.manager.stateOf(widget.tileKey);
    _dl = widget.manager.downloadOf(widget.tileKey);
    widget.manager.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.manager.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _state = widget.manager.stateOf(widget.tileKey);
      _dl = widget.manager.downloadOf(widget.tileKey);
    });
  }

  bool get _isDownloading =>
      _dl?.status == ZoneDownloadStatus.downloading;

  Future<void> _download() async {
    widget.manager.downloadTile(widget.tileKey);
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: WSColors.snowWhite,
        title: Text('Supprimer ${widget.tileKey} ?'),
        content: const Text(
            'Toutes les données installées pour cette zone seront supprimées.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: WSColors.avalancheRed),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await widget.manager.deleteTile(widget.tileKey);
      if (mounted) Navigator.pop(context);
    }
  }

  String get _name {
    // Donne un nom lisible depuis la clé (ex: N45E005 → "45°N 5°E")
    final (lat, lng) = OfflineZoneManager.swFromKey(widget.tileKey);
    return '${lat.abs().toInt()}°${lat >= 0 ? 'N' : 'S'} '
        '${lng.abs().toInt()}°${lng >= 0 ? 'E' : 'W'} — ${widget.tileKey}';
  }

  @override
  Widget build(BuildContext context) {
    final needsDownload = !_state.hgtInstalled ||
        (_state.wsrAvailable && !_state.wsrInstalled);

    return Container(
      decoration: const BoxDecoration(
        color: WSColors.snowWhite,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(WSRadius.xl)),
      ),
      padding: const EdgeInsets.fromLTRB(
          WSSpacing.xl, WSSpacing.lg, WSSpacing.xl, WSSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Poignée
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

          Text(_name, style: WSText.title),
          const SizedBox(height: WSSpacing.lg),

          // Statut HGT
          _DataRow(
            icon: Icons.terrain_outlined,
            label: 'Altitude (isochrones)',
            installed: _state.hgtInstalled,
            available: true,
            progress: _isDownloading ? _dl!.hgtProgress : null,
          ),
          const SizedBox(height: WSSpacing.sm),

          // Statut WSR
          _DataRow(
            icon: Icons.route_outlined,
            label: 'Routage (itinéraires)',
            installed: _state.wsrInstalled,
            available: _state.wsrAvailable,
            progress: _isDownloading ? _dl!.wsrProgress : null,
          ),

          // Barre de progression globale
          if (_isDownloading) ...[
            const SizedBox(height: WSSpacing.lg),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: _dl!.totalProgress,
                minHeight: 4,
                backgroundColor: WSColors.glacierLight,
                valueColor:
                    const AlwaysStoppedAnimation(WSColors.glacierBlue),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Téléchargement… ${(_dl!.totalProgress * 100).toStringAsFixed(0)}%',
              style: WSText.micro,
            ),
          ],

          // Erreur
          if (_dl?.status == ZoneDownloadStatus.error) ...[
            const SizedBox(height: WSSpacing.sm),
            Row(children: [
              const Icon(Icons.error_outline,
                  size: 14, color: WSColors.avalancheRed),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _dl!.error ?? 'Erreur',
                  style: WSText.micro
                      .copyWith(color: WSColors.avalancheRed),
                ),
              ),
            ]),
          ],

          const SizedBox(height: WSSpacing.xl),

          // Actions
          if (!_isDownloading)
            Row(
              children: [
                if (_state.anyInstalled) ...[
                  OutlinedButton.icon(
                    onPressed: _delete,
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Supprimer'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: WSColors.avalancheRed,
                      side: const BorderSide(
                          color: WSColors.avalancheRed, width: 0.5),
                    ),
                  ),
                  const SizedBox(width: WSSpacing.md),
                ],
                if (needsDownload)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _download,
                      icon: const Icon(Icons.download_outlined, size: 16),
                      label: Text(_state.anyInstalled
                          ? 'Compléter'
                          : 'Télécharger'),
                    ),
                  ),
                if (!needsDownload && !_state.anyInstalled)
                  Text('Non disponible dans cette zone',
                      style: WSText.caption),
              ],
            ),
        ],
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool installed;
  final bool available;
  final double? progress; // non-null = en cours

  const _DataRow({
    required this.icon,
    required this.label,
    required this.installed,
    required this.available,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    String statusLabel;
    if (progress != null) {
      statusColor = WSColors.glacierBlue;
      statusLabel = '${(progress! * 100).toStringAsFixed(0)}%';
    } else if (installed) {
      statusColor = WSColors.powderGreen;
      statusLabel = 'Installé';
    } else if (available) {
      statusColor = WSColors.stoneGray;
      statusLabel = 'Non installé';
    } else {
      statusColor = WSColors.stoneGray;
      statusLabel = 'Indisponible';
    }

    return Row(
      children: [
        Icon(icon, size: 18,
            color: installed ? WSColors.glacierBlue : WSColors.stoneGray),
        const SizedBox(width: WSSpacing.md),
        Expanded(child: Text(label, style: WSText.body)),
        Text(statusLabel,
            style: WSText.caption.copyWith(
                color: statusColor, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
