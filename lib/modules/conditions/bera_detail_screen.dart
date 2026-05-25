// lib/modules/conditions/bera_detail_screen.dart
//
// Écran de lecture du BERA enrichi d'un massif.
// Source : Tinevagio/Ski-touring-live (mis à jour quotidiennement).
//
// Structure de l'écran :
//   - Bandeau identité (massif, dép, zone, date)
//   - Niveau de risque (avec split altitude si applicable, palette officielle)
//   - Pentes dangereuses (rose des vents 8 secteurs)
//   - Enneigement (limites N/S + tableau hauteurs par altitude)
//   - Neige fraîche des 6 derniers jours (mini-bar chart textuel)
//   - Texte qualité du manteau (lecture)
//   - Footer source + bouton rafraîchir

import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import 'models/bera_full.dart';
import 'services/bera_full_service.dart';

class BeraDetailScreen extends StatefulWidget {
  /// Nom du massif (ex: "Belledonne"). Doit matcher exactement le champ
  /// `massif` du JSON BERA (case-insensitive géré côté service).
  final String massifName;

  const BeraDetailScreen({super.key, required this.massifName});

  /// Helper pour ouvrir l'écran depuis un autre.
  static Future<void> open(BuildContext context, String massifName) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BeraDetailScreen(massifName: massifName),
      ),
    );
  }

  @override
  State<BeraDetailScreen> createState() => _BeraDetailScreenState();
}

class _BeraDetailScreenState extends State<BeraDetailScreen> {
  late Future<BeraFull?> _future;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _future = _load(forceRefresh: false);
  }

  Future<BeraFull?> _load({required bool forceRefresh}) {
    return BeraFullService()
        .getByMassifName(widget.massifName, forceRefresh: forceRefresh);
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      final fresh = _load(forceRefresh: true);
      setState(() => _future = fresh);
      await fresh;
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('BERA ${widget.massifName}'),
        actions: [
          IconButton(
            tooltip: 'Rafraîchir',
            icon: _refreshing
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _refreshing ? null : _refresh,
          ),
        ],
      ),
      body: FutureBuilder<BeraFull?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _ErrorBox(message: '${snap.error}', onRetry: _refresh);
          }
          final bera = snap.data;
          if (bera == null) {
            return _ErrorBox(
              message: 'Massif "${widget.massifName}" introuvable '
                  'dans le bulletin BERA actuel.',
              onRetry: _refresh,
            );
          }
          return _BeraBody(bera: bera);
        },
      ),
    );
  }
}

// ─── Corps de l'écran ────────────────────────────────────────────────────────

class _BeraBody extends StatelessWidget {
  final BeraFull bera;
  const _BeraBody({required this.bera});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: WSSpacing.lg,
        vertical: WSSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Identity(bera: bera),
          const SizedBox(height: WSSpacing.xl),
          _RiskBlock(bera: bera),
          const SizedBox(height: WSSpacing.xl),
          if (bera.pentesDangereuses.hasAny) ...[
            _DangerousAspectsBlock(aspects: bera.pentesDangereuses),
            const SizedBox(height: WSSpacing.xl),
          ],
          _SnowDepthBlock(bera: bera),
          const SizedBox(height: WSSpacing.xl),
          if (bera.neigeFraiche.isNotEmpty) ...[
            _FreshSnowBlock(items: bera.neigeFraiche,
                            altMesureM: bera.altiMesureFraicheM),
            const SizedBox(height: WSSpacing.xl),
          ],
          if (bera.qualiteTexte != null && bera.qualiteTexte!.trim().isNotEmpty) ...[
            _QualityBlock(text: bera.qualiteTexte!),
            const SizedBox(height: WSSpacing.xl),
          ],
          _Footer(),
        ],
      ),
    );
  }
}

class _Identity extends StatelessWidget {
  final BeraFull bera;
  const _Identity({required this.bera});

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (bera.departement != null) parts.add(bera.departement!);
    if (bera.zone != null) parts.add(bera.zone!);
    final sub = parts.join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(bera.massif,
            style: WSText.display.copyWith(fontSize: 28)),
        const SizedBox(height: 4),
        if (sub.isNotEmpty)
          Text(sub,
              style: WSText.body.copyWith(color: WSColors.stoneGray)),
        if (bera.dateEnneigement != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.event,
                  size: 14, color: WSColors.stoneGray),
              const SizedBox(width: 4),
              Text('Bulletin du ${_formatDate(bera.dateEnneigement!)}',
                  style: WSText.micro.copyWith(color: WSColors.stoneGray)),
            ],
          ),
        ],
      ],
    );
  }
}

class _RiskBlock extends StatelessWidget {
  final BeraFull bera;
  const _RiskBlock({required this.bera});

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Risque d\'avalanche',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (bera.hasAltitudeSplit) ...[
            _RiskRow(
              label: 'Au-dessus de ${bera.risqueAltitudeM} m',
              risk: bera.risqueHaut,
            ),
            const SizedBox(height: WSSpacing.sm),
            _RiskRow(
              label: 'En-dessous de ${bera.risqueAltitudeM} m',
              risk: bera.risqueBas,
            ),
          ] else if (bera.risqueBas != null) ...[
            _RiskRow(
              label: 'Niveau de risque',
              risk: bera.risqueBas,
            ),
          ] else
            Text('Pas de niveau de risque communiqué.',
                style: WSText.body.copyWith(color: WSColors.stoneGray)),
        ],
      ),
    );
  }
}

class _RiskRow extends StatelessWidget {
  final String label;
  final int? risk;
  const _RiskRow({required this.label, required this.risk});

  @override
  Widget build(BuildContext context) {
    final r = risk ?? 0;
    final color = r >= 1 ? WSColors.beraColor(r) : WSColors.stoneGray;
    return Row(
      children: [
        Container(
          width: 22, height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Text(
            r >= 1 ? '$r' : '?',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: WSSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: WSText.body),
              if (r >= 1)
                Text(WSColors.beraLabel(r),
                    style: WSText.micro
                        .copyWith(color: WSColors.stoneGray)),
            ],
          ),
        ),
      ],
    );
  }
}

class _DangerousAspectsBlock extends StatelessWidget {
  final DangerousAspects aspects;
  const _DangerousAspectsBlock({required this.aspects});

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Pentes dangereuses',
      child: Column(
        children: [
          SizedBox(
            height: 160,
            child: CustomPaint(painter: _CompassRosePainter(aspects)),
          ),
          const SizedBox(height: WSSpacing.sm),
          Text(
            aspects.dangerousList.join(' · '),
            style: WSText.body.copyWith(
              fontWeight: FontWeight.w600,
              color: WSColors.avalancheRed,
            ),
          ),
        ],
      ),
    );
  }
}

/// Rose des vents 8 secteurs. Pétales rouges = secteurs dangereux,
/// gris pâle = OK.
class _CompassRosePainter extends CustomPainter {
  final DangerousAspects aspects;
  const _CompassRosePainter(this.aspects);

  static const List<String> _labels = ['N','NE','E','SE','S','SO','O','NO'];

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 20;

    final flags = [
      aspects.n, aspects.ne, aspects.e, aspects.se,
      aspects.s, aspects.sw, aspects.w, aspects.nw,
    ];

    // 8 pétales de 45° chacun, séparés par un petit gap visuel.
    const gapDeg = 2.0;
    const sweepDeg = 45.0 - gapDeg * 2;
    final sweepRad = sweepDeg * math.pi / 180;

    final dangerPaint = Paint()..color = WSColors.avalancheRed;
    final okPaint     = Paint()..color = WSColors.glacierLight;

    for (var i = 0; i < 8; i++) {
      // Le secteur i (N) doit être centré "en haut" : -90° puis i*45°.
      final centerDeg = -90 + i * 45;
      final startDeg = centerDeg - sweepDeg / 2;
      final startRad = startDeg * math.pi / 180;

      final rect = Rect.fromCircle(center: c, radius: radius);
      canvas.drawArc(rect, startRad, sweepRad, true,
          flags[i] ? dangerPaint : okPaint);
    }

    // Labels cardinaux à l'extérieur des pétales.
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < 8; i++) {
      final centerRad = (-90 + i * 45) * math.pi / 180;
      final lx = c.dx + (radius + 12) * math.cos(centerRad);
      final ly = c.dy + (radius + 12) * math.sin(centerRad);
      tp.text = TextSpan(
        text: _labels[i],
        style: TextStyle(
          color: flags[i] ? WSColors.avalancheRed : WSColors.slateDark,
          fontSize: 11,
          fontWeight: flags[i] ? FontWeight.w700 : FontWeight.w500,
        ),
      );
      tp.layout();
      tp.paint(canvas, Offset(lx - tp.width / 2, ly - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_CompassRosePainter old) =>
      old.aspects.dangerousList.toString() != aspects.dangerousList.toString();
}

class _SnowDepthBlock extends StatelessWidget {
  final BeraFull bera;
  const _SnowDepthBlock({required this.bera});

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Enneigement',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (bera.limiteNordM != null && bera.limiteNordM! > 0)
            _LimitRow(
              icon: Icons.arrow_upward,
              label: 'Limite skiable Nord',
              value: '${bera.limiteNordM} m',
            ),
          if (bera.limiteSudM != null && bera.limiteSudM! > 0)
            _LimitRow(
              icon: Icons.arrow_downward,
              label: 'Limite skiable Sud',
              value: '${bera.limiteSudM} m',
            ),
          if (bera.enneigement.isNotEmpty) ...[
            const SizedBox(height: WSSpacing.md),
            Container(
              padding: const EdgeInsets.all(WSSpacing.md),
              decoration: BoxDecoration(
                color: WSColors.glacierLight,
                borderRadius: BorderRadius.circular(WSRadius.md),
              ),
              child: _SnowTable(items: bera.enneigement),
            ),
          ],
        ],
      ),
    );
  }
}

class _LimitRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _LimitRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: WSColors.stoneGray),
          const SizedBox(width: 6),
          Text(label, style: WSText.body),
          const SizedBox(width: 6),
          Text(value,
              style: WSText.body.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _SnowTable extends StatelessWidget {
  final List<BeraSnowDepth> items;
  const _SnowTable({required this.items});

  @override
  Widget build(BuildContext context) {
    final hStyle = WSText.micro.copyWith(
      color: WSColors.stoneGray, fontWeight: FontWeight.w600);
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Text('Altitude', style: hStyle)),
            Expanded(child: Text('Nord',     style: hStyle, textAlign: TextAlign.center)),
            Expanded(child: Text('Sud',      style: hStyle, textAlign: TextAlign.center)),
          ],
        ),
        const SizedBox(height: 4),
        const Divider(height: 8),
        ...items.reversed.map((s) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text('${s.alti} m', style: WSText.body)),
                  Expanded(
                    child: Text(
                      s.nCm != null ? '${s.nCm} cm' : '—',
                      style: WSText.body, textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      s.sCm != null ? '${s.sCm} cm' : '—',
                      style: WSText.body, textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }
}

class _FreshSnowBlock extends StatelessWidget {
  final List<BeraFreshSnow> items;
  final int? altMesureM;
  const _FreshSnowBlock({required this.items, this.altMesureM});

  @override
  Widget build(BuildContext context) {
    final maxValue = items
        .map((e) => e.centralCm)
        .fold<int>(0, (a, b) => b > a ? b : a)
        .clamp(1, 9999);
    return _Section(
      title: altMesureM != null
          ? 'Neige fraîche à ${altMesureM} m'
          : 'Neige fraîche',
      child: Column(
        children: items.map((e) {
          final ratio = e.centralCm / maxValue;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 54,
                  child: Text(_shortDate(e.date),
                      style: WSText.micro
                          .copyWith(color: WSColors.stoneGray)),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: WSColors.glacierLight,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: ratio.clamp(0.0, 1.0),
                        child: Container(
                          height: 8,
                          decoration: BoxDecoration(
                            color: WSColors.glacierBlue,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  child: Text('${e.centralCm} cm',
                      style: WSText.body, textAlign: TextAlign.right),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _QualityBlock extends StatelessWidget {
  final String text;
  const _QualityBlock({required this.text});

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Qualité du manteau',
      child: Container(
        padding: const EdgeInsets.all(WSSpacing.md),
        decoration: BoxDecoration(
          color: WSColors.glacierLight,
          borderRadius: BorderRadius.circular(WSRadius.md),
          border: Border.all(color: WSColors.glacierMid, width: 0.5),
        ),
        child: Text(
          text.trim(),
          style: WSText.body.copyWith(height: 1.5),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(WSSpacing.md),
      decoration: BoxDecoration(
        color: WSColors.glacierLight,
        borderRadius: BorderRadius.circular(WSRadius.md),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline,
              size: 16, color: WSColors.stoneGray),
          const SizedBox(width: WSSpacing.sm),
          Expanded(
            child: Text(
              'Source : Météo France, agrégé par '
              'ski-touring-live.fr (mis à jour quotidiennement).',
              style: WSText.micro.copyWith(color: WSColors.stoneGray),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.toUpperCase(),
            style: WSText.micro.copyWith(
              color: WSColors.stoneGray,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            )),
        const SizedBox(height: WSSpacing.sm),
        child,
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBox({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(WSSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: WSColors.stoneGray),
            const SizedBox(height: WSSpacing.md),
            Text(message,
                textAlign: TextAlign.center,
                style: WSText.body.copyWith(color: WSColors.stoneGray)),
            const SizedBox(height: WSSpacing.lg),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Helpers format ─────────────────────────────────────────────────────────

String _formatDate(String iso) {
  // "2026-05-24" → "24 mai 2026"
  final parts = iso.split('-');
  if (parts.length != 3) return iso;
  final y = parts[0];
  final m = int.tryParse(parts[1]) ?? 0;
  final d = int.tryParse(parts[2]) ?? 0;
  const months = [
    '', 'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
  ];
  if (m < 1 || m > 12 || d < 1) return iso;
  return '$d ${months[m]} $y';
}

String _shortDate(String iso) {
  final parts = iso.split('-');
  if (parts.length != 3) return iso;
  return '${parts[2]}/${parts[1]}';
}