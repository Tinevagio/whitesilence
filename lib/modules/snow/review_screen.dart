// lib/modules/snow/review_screen.dart
//
// Liste de toutes les observations groupées par date.
// Migré depuis Hey Snowy avec re-style WhiteSilence.

import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/snow_palette.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import 'edit_observation_screen.dart';
import 'models/observation.dart';
import 'snow_controller.dart';
import 'snow_dao.dart';

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final SnowDao _dao = SnowDao();
  final SnowController _controller = SnowController();
  List<Observation> _obs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await _dao.loadAll();
    setState(() {
      _obs = all;
      _loading = false;
    });
  }

  Map<String, List<Observation>> _groupByDate() {
    final groups = <String, List<Observation>>{};
    for (final o in _obs) {
      groups.putIfAbsent(_dateLabel(o.timestamp), () => []).add(o);
    }
    return groups;
  }

  String _dateLabel(DateTime dt) {
    final now    = DateTime.now();
    final today  = DateTime(now.year, now.month, now.day);
    final obsDay = DateTime(dt.year, dt.month, dt.day);
    final diff   = today.difference(obsDay).inDays;
    if (diff == 0) return "Aujourd'hui";
    if (diff == 1) return 'Hier';
    return '${dt.day.toString().padLeft(2, "0")}/'
           '${dt.month.toString().padLeft(2, "0")}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Observations'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _obs.isEmpty
              ? const _EmptyState()
              : _buildList(),
    );
  }

  Widget _buildList() {
    final groups = _groupByDate();
    final dates = groups.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: WSSpacing.lg,
        vertical: WSSpacing.md,
      ),
      itemCount: dates.length,
      itemBuilder: (_, dateIdx) {
        final date = dates[dateIdx];
        final items = groups[date]!;
        return Padding(
          padding: const EdgeInsets.only(bottom: WSSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  left: WSSpacing.xs,
                  bottom: WSSpacing.sm,
                ),
                child: Text(
                  date.toUpperCase(),
                  style: WSText.micro.copyWith(color: WSColors.stoneGray),
                ),
              ),
              for (final o in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: WSSpacing.sm),
                  child: _ObservationCard(
                    obs: o,
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => EditObservationScreen(observation: o),
                        ),
                      );
                      _load(); // recharge après retour (changements possibles)
                    },
                    onDelete: () async {
                      await _controller.deleteObservation(o);
                      _load();
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(WSSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.ac_unit_outlined,
                size: 48, color: WSColors.stoneGray),
            const SizedBox(height: WSSpacing.md),
            const Text(
              'Aucune observation pour l\'instant.',
              style: WSText.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: WSSpacing.sm),
            Text(
              'Active le module Neige et tape sur le micro pour enregistrer ta première observation.',
              style: WSText.caption,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ObservationCard extends StatelessWidget {
  final Observation obs;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ObservationCard({
    required this.obs,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final color = SnowPalette.colorForUserType(obs.snowType);
    final timeStr = '${obs.timestamp.hour.toString().padLeft(2, "0")}:'
        '${obs.timestamp.minute.toString().padLeft(2, "0")}';

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: WSSpacing.sm),
              Text(
                obs.snowType ?? 'Non traitée',
                style: WSText.body.copyWith(
                  fontWeight: FontWeight.w500,
                  color: obs.isEnriched ? WSColors.slateDark : WSColors.stoneGray,
                ),
              ),
              const Spacer(),
              Text(timeStr, style: WSText.caption),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 16),
                onPressed: onDelete,
                color: WSColors.stoneGray,
                padding: const EdgeInsets.only(left: WSSpacing.sm),
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          if (obs.altitudeM != null || obs.aspect != null) ...[
            const SizedBox(height: WSSpacing.xs),
            Text(
              [
                if (obs.altitudeM != null) '${obs.altitudeM!.round()} m',
                if (obs.aspect != null) obs.aspect,
                if (obs.depthCm != null) '${obs.depthCm} cm',
              ].whereType<String>().join(' · '),
              style: WSText.caption,
            ),
          ],
          if (obs.rawNotes != null && obs.rawNotes!.isNotEmpty) ...[
            const SizedBox(height: WSSpacing.sm),
            Text(obs.rawNotes!, style: WSText.body),
          ] else if (obs.transcript != null) ...[
            const SizedBox(height: WSSpacing.sm),
            Text(
              '« ${obs.transcript} »',
              style: WSText.caption.copyWith(fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
        ),
      ),
    );
  }
}
