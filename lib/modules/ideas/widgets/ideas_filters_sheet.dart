// lib/modules/ideas/widgets/ideas_filters_sheet.dart
//
// Bottom sheet de configuration des filtres de recherche.
// Pas mal de critères, on a regroupé pour rester lisible.

import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../ideas_controller.dart';
import '../models/ideas_filter.dart';
import '../services/ideas_preferences.dart';

class IdeasFiltersSheet extends StatefulWidget {
  final IdeasController controller;
  const IdeasFiltersSheet({super.key, required this.controller});

  @override
  State<IdeasFiltersSheet> createState() => _IdeasFiltersSheetState();
}

class _IdeasFiltersSheetState extends State<IdeasFiltersSheet> {
  late IdeasFilter _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.controller.filter;
    // Si les métadonnées n'ont pas été chargées au démarrage (panne réseau,
    // backend endormi…), on retente maintenant. La sheet rebuild auto via
    // ListenableBuilder quand les massifs arrivent.
    widget.controller.ensureMetadata();
  }

  static const _allExpos = ['N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO'];
  static const _allNiveaux = ['S1', 'S2', 'S3', 'S4', 'S5'];

  void _toggleExpo(String e) {
    final newSet = Set<String>.from(_draft.expositions);
    if (newSet.contains(e)) {
      newSet.remove(e);
    } else {
      newSet.add(e);
    }
    if (newSet.isEmpty) return; // empêche la sélection vide
    setState(() => _draft = _draft.copyWith(expositions: newSet));
  }

  void _toggleMassif(String m) {
    final newSet = Set<String>.from(_draft.massifs);
    if (newSet.contains(m)) {
      newSet.remove(m);
    } else {
      newSet.add(m);
    }
    setState(() => _draft = _draft.copyWith(massifs: newSet));
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _draft.date,
      firstDate: now,
      lastDate: now.add(const Duration(days: 7)),
      locale: const Locale('fr', 'FR'),
    );
    if (picked != null) {
      setState(() => _draft = _draft.copyWith(date: picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    // ListenableBuilder pour que la sheet rebuild quand les métadonnées
    // arrivent (cas : panne réseau au démarrage, retry réussit à l'ouverture
    // de la sheet → la liste des massifs passe de "chargement" à remplie).
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final meta = widget.controller.metadata;
        final massifs = meta?.massifs ?? const <String>[];

        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: WSColors.snowWhite,
          borderRadius: BorderRadius.vertical(top: Radius.circular(WSRadius.xl)),
        ),
        child: Column(
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.only(top: WSSpacing.sm),
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: WSColors.glacierMid,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: WSSpacing.md),
            // Titre
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: WSSpacing.xl),
              child: Row(
                children: [
                  const Icon(Icons.tune, size: 20),
                  const SizedBox(width: WSSpacing.sm),
                  const Text('Filtres', style: WSText.title),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Contenu scrollable
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(WSSpacing.xl),
                children: [
                  // ── Date ─────────────────────────────────────────────────
                  _SectionLabel('Date de sortie'),
                  OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    label: Text(_formatDate(_draft.date)),
                  ),

                  const SizedBox(height: WSSpacing.lg),
                  // ── Niveau ───────────────────────────────────────────────
                  _SectionLabel('Niveau de ski'),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final n in _allNiveaux)
                        ChoiceChip(
                          label: Text(n),
                          selected: _draft.niveau == n,
                          onSelected: (_) => setState(() =>
                              _draft = _draft.copyWith(niveau: n)),
                        ),
                    ],
                  ),

                  const SizedBox(height: WSSpacing.lg),
                  // ── Dénivelé positif ─────────────────────────────────────
                  _SectionLabel(
                    'Dénivelé positif : ${_draft.dplusMin}-${_draft.dplusMax} m',
                  ),
                  RangeSlider(
                    min: 200, max: 2500, divisions: 23,
                    values: RangeValues(
                      _draft.dplusMin.toDouble(),
                      _draft.dplusMax.toDouble(),
                    ),
                    labels: RangeLabels(
                      '${_draft.dplusMin}m',
                      '${_draft.dplusMax}m',
                    ),
                    onChanged: (v) => setState(() => _draft = _draft.copyWith(
                          dplusMin: v.start.round(),
                          dplusMax: v.end.round(),
                        )),
                  ),

                  const SizedBox(height: WSSpacing.lg),
                  // ── Expositions ──────────────────────────────────────────
                  _SectionLabel('Expositions acceptables'),
                  Wrap(
                    spacing: 6, runSpacing: 6,
                    children: [
                      for (final e in _allExpos)
                        FilterChip(
                          label: Text(e),
                          selected: _draft.expositions.contains(e),
                          onSelected: (_) => _toggleExpo(e),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    icon: const Icon(Icons.wb_sunny_outlined, size: 16),
                    label: const Text('Éviter expositions Sud'),
                    onPressed: () => setState(() {
                      _draft = _draft.copyWith(
                          expositions: {'N', 'NE', 'E', 'O', 'NO'});
                    }),
                  ),

                  const SizedBox(height: WSSpacing.lg),
                  // ── Massifs ─────────────────────────────────────────────
                  _SectionLabel(
                    massifs.isEmpty
                        ? 'Massifs (chargement…)'
                        : 'Massifs (${_draft.massifs.isEmpty ? "tous" : _draft.massifs.length})',
                  ),
                  if (massifs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: WSSpacing.sm),
                      child: Text(
                        'En attente du backend…',
                        style: WSText.micro,
                      ),
                    )
                  else
                    Wrap(
                      spacing: 6, runSpacing: 6,
                      children: [
                        for (final m in massifs)
                          FilterChip(
                            label: Text(m, style: const TextStyle(fontSize: 12)),
                            selected: _draft.massifs.contains(m),
                            onSelected: (_) => _toggleMassif(m),
                          ),
                      ],
                    ),

                  const SizedBox(height: WSSpacing.lg),
                  // ── Nombre de résultats ─────────────────────────────────
                  _SectionLabel('Nombre de propositions : ${_draft.nResults}'),
                  Slider(
                    min: 3, max: 20, divisions: 17,
                    value: _draft.nResults.toDouble(),
                    onChanged: (v) => setState(() => _draft =
                        _draft.copyWith(nResults: v.round())),
                  ),

                  const SizedBox(height: WSSpacing.lg),
                  // ── Score IA ────────────────────────────────────────────
                  SwitchListTile(
                    title: const Text('Inclure le score IA',
                        style: WSText.body),
                    subtitle: const Text(
                      'Estimation qualité neige (ajoute ~30s au temps de recherche)',
                      style: WSText.micro,
                    ),
                    value: _draft.includeAi,
                    onChanged: (v) => setState(() =>
                        _draft = _draft.copyWith(includeAi: v)),
                  ),

                  const SizedBox(height: WSSpacing.lg),
                  // ── Sorties masquées et wish-list ──────────────────────
                  // Observation des prefs pour afficher des compteurs à jour.
                  ListenableBuilder(
                    listenable: IdeasPreferences(),
                    builder: (context, _) {
                      final prefs = IdeasPreferences();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SectionLabel(
                            'Mes listes (${prefs.wishlistCount} en wish-list, '
                            '${prefs.hiddenCount} masquées)',
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Voir les sorties masquées',
                                style: WSText.body),
                            subtitle: const Text(
                              'Utile pour démasquer une sortie précédemment cachée',
                              style: WSText.micro,
                            ),
                            value: _draft.showHidden,
                            onChanged: (v) => setState(() =>
                                _draft = _draft.copyWith(showHidden: v)),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: WSSpacing.xxxl),
                ],
              ),
            ),
            // Footer : bouton primary
            Container(
              padding: const EdgeInsets.all(WSSpacing.lg),
              decoration: BoxDecoration(
                color: WSColors.snowWhite,
                border: Border(
                  top: BorderSide(color: WSColors.glacierMid, width: 0.5),
                ),
              ),
              child: SafeArea(
                top: false,
                child: FilledButton.icon(
                  onPressed: () {
                    widget.controller.updateFilter(_draft);
                    Navigator.of(context).pop();
                    widget.controller.search();
                  },
                  icon: const Icon(Icons.search, size: 20),
                  label: const Text('Trouver mes sorties'),
                ),
              ),
            ),
          ],
        ),
      ),
        );
      },
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      'jan', 'fév', 'mars', 'avril', 'mai', 'juin',
      'juil', 'août', 'sept', 'oct', 'nov', 'déc',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: WSSpacing.sm),
      child: Text(
        text,
        style: WSText.body.copyWith(
          fontWeight: FontWeight.w600,
          color: WSColors.slateDark,
        ),
      ),
    );
  }
}
