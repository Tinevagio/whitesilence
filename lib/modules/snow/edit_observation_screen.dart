// lib/modules/snow/edit_observation_screen.dart
//
// Édition manuelle d'une observation : corriger le type de neige détecté par
// l'IA, ajuster l'orientation/stabilité, modifier les notes.
//
// Migré depuis Hey Snowy (lib/screens/edit_observation_screen.dart) avec
// re-style WhiteSilence (palette claire, choix via SegmentedButton / Wrap
// dans la charte). Logique métier identique :
//   - Sauvegarde locale via SnowDao
//   - Si l'obs avait déjà été uploadée sur Supabase → re-upload pour propager
//     la correction
//   - Notifie SnowController.refresh() pour que les pins de la carte
//     soient mis à jour

import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import 'models/observation.dart';
import 'services/supabase_service.dart';
import 'snow_controller.dart';
import 'snow_dao.dart';

class EditObservationScreen extends StatefulWidget {
  final Observation observation;
  const EditObservationScreen({super.key, required this.observation});

  @override
  State<EditObservationScreen> createState() => _EditObservationScreenState();
}

class _EditObservationScreenState extends State<EditObservationScreen> {
  final SnowDao _dao = SnowDao();
  final SupabaseService _supabase = SupabaseService();

  late String? _snowType;
  late int? _stabilityScore;
  late String? _aspect;
  late TextEditingController _notesController;
  late TextEditingController _depthController;
  bool _saving = false;
  bool _dirty = false;

  static const _snowTypes = [
    'poudre', 'moquette', 'transfo', 'béton',
    'croûte', 'ventée', 'humide', 'purge', 'lourde', 'autre',
  ];

  static const _aspects = [
    'N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO',
  ];

  @override
  void initState() {
    super.initState();
    _snowType        = widget.observation.snowType;
    _stabilityScore  = widget.observation.stabilityScore;
    _aspect          = widget.observation.aspect;
    _notesController = TextEditingController(
        text: widget.observation.rawNotes ?? '');
    _depthController = TextEditingController(
        text: widget.observation.depthCm?.toString() ?? '');
    _notesController.addListener(_markDirty);
    _depthController.addListener(_markDirty);
  }

  @override
  void dispose() {
    _notesController.dispose();
    _depthController.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    final obs = widget.observation;
    obs.snowType       = _snowType;
    obs.stabilityScore = _stabilityScore;
    obs.aspect         = _aspect;
    obs.rawNotes       = _notesController.text.trim().isEmpty
                          ? null : _notesController.text.trim();
    final depthText = _depthController.text.trim();
    obs.depthCm = depthText.isEmpty ? null : int.tryParse(depthText);

    // 1. Sauvegarde locale
    await _dao.update(obs);

    // 2. Re-propage sur Supabase si l'obs avait été partagée
    if (obs.uploaded) {
      await _supabase.uploadObservation(obs);
    }

    // 3. Rafraîchit le contrôleur pour mettre à jour les pins sur la carte
    await SnowController().refreshObservations();

    setState(() => _saving = false);
    if (mounted) Navigator.pop(context, obs);
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: WSColors.snowWhite,
        title: const Text('Abandonner les modifications ?'),
        content: const Text(
          'Tes changements n\'ont pas été sauvegardés.',
          style: WSText.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuer l\'édition'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: WSColors.avalancheRed,
            ),
            child: const Text('Abandonner'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: WSColors.snowWhite,
        title: const Text('Supprimer cette observation ?'),
        content: const Text(
          'Cette action est irréversible. L\'observation sera retirée '
          'localement et de la base communautaire si elle y était.',
          style: WSText.body,
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

    if (ok == true) {
      final obs = widget.observation;
      await _dao.delete(obs.id);
      if (obs.uploaded) {
        await _supabase.deleteObservation(obs.id);
      }
      await SnowController().refreshObservations();
      if (mounted) Navigator.pop(context, null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Modifier'),
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_outline, color: WSColors.avalancheRed),
              onPressed: _confirmDelete,
              tooltip: 'Supprimer',
            ),
            TextButton(
              onPressed: (_saving || !_dirty) ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(WSColors.glacierBlue),
                      ),
                    )
                  : Text(
                      'Sauvegarder',
                      style: TextStyle(
                        color: _dirty ? WSColors.glacierBlue : WSColors.stoneGray,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(WSSpacing.lg),
          children: [
            // ── Transcript (lecture seule) ──────────────────────────────
            if (widget.observation.transcript != null &&
                widget.observation.transcript!.isNotEmpty) ...[
              _label('Transcription'),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(WSSpacing.md),
                decoration: BoxDecoration(
                  color: WSColors.glacierLight,
                  borderRadius: BorderRadius.circular(WSRadius.md),
                ),
                child: Text(
                  '« ${widget.observation.transcript} »',
                  style: WSText.body.copyWith(
                    fontStyle: FontStyle.italic,
                    color: WSColors.stoneGray,
                  ),
                ),
              ),
              const SizedBox(height: WSSpacing.xl),
            ],

            // ── Type de neige ──────────────────────────────────────────
            _label('Type de neige'),
            Wrap(
              spacing: WSSpacing.sm,
              runSpacing: WSSpacing.sm,
              children: [
                for (final type in _snowTypes)
                  _SelectableChip(
                    label: type,
                    selected: _snowType == type,
                    color: WSColors.snowTypeColor(type),
                    onTap: () {
                      setState(() {
                        _snowType = type;
                        _dirty = true;
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: WSSpacing.xl),

            // ── Orientation ────────────────────────────────────────────
            _label('Orientation (versant)'),
            Wrap(
              spacing: WSSpacing.sm,
              runSpacing: WSSpacing.sm,
              children: [
                _SelectableChip(
                  label: '—',
                  selected: _aspect == null,
                  onTap: () {
                    setState(() {
                      _aspect = null;
                      _dirty = true;
                    });
                  },
                ),
                for (final asp in _aspects)
                  _SelectableChip(
                    label: asp,
                    selected: _aspect == asp,
                    onTap: () {
                      setState(() {
                        _aspect = asp;
                        _dirty = true;
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: WSSpacing.xl),

            // ── Stabilité ──────────────────────────────────────────────
            _label('Stabilité'),
            Row(
              children: [
                Text('1', style: WSText.caption),
                Expanded(
                  child: Slider(
                    value: (_stabilityScore ?? 3).toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    activeColor: WSColors.glacierBlue,
                    inactiveColor: WSColors.glacierMid,
                    label: '${_stabilityScore ?? 3}',
                    onChanged: (v) {
                      setState(() {
                        _stabilityScore = v.toInt();
                        _dirty = true;
                      });
                    },
                  ),
                ),
                Text('5', style: WSText.caption),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: WSSpacing.sm),
              child: Text(
                _stabilityScore == null
                    ? 'Non précisée'
                    : _stabilityLabel(_stabilityScore!),
                style: WSText.caption,
              ),
            ),
            const SizedBox(height: WSSpacing.xl),

            // ── Épaisseur ──────────────────────────────────────────────
            _label('Épaisseur neige (cm)'),
            TextField(
              controller: _depthController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                filled: true,
                fillColor: WSColors.glacierLight,
                hintText: 'p. ex. 25',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(WSRadius.md)),
                  borderSide: BorderSide.none,
                ),
                suffixText: 'cm',
              ),
            ),
            const SizedBox(height: WSSpacing.xl),

            // ── Notes ──────────────────────────────────────────────────
            _label('Notes'),
            TextField(
              controller: _notesController,
              maxLines: 4,
              decoration: const InputDecoration(
                filled: true,
                fillColor: WSColors.glacierLight,
                hintText: 'Détails libres sur les conditions…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(WSRadius.md)),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: WSSpacing.xl),

            // ── Position (lecture seule) ───────────────────────────────
            _label('Position'),
            Container(
              padding: const EdgeInsets.all(WSSpacing.md),
              decoration: BoxDecoration(
                color: WSColors.glacierLight,
                borderRadius: BorderRadius.circular(WSRadius.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.observation.altitudeM != null
                        ? '${widget.observation.altitudeM!.round()} m d\'altitude'
                        : 'Altitude inconnue',
                    style: WSText.body,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${widget.observation.lat.toStringAsFixed(5)}, '
                    '${widget.observation.lon.toStringAsFixed(5)}',
                    style: WSText.caption,
                  ),
                ],
              ),
            ),
            const SizedBox(height: WSSpacing.xxl),

            if (widget.observation.uploaded)
              Container(
                padding: const EdgeInsets.all(WSSpacing.md),
                decoration: BoxDecoration(
                  color: WSColors.glacierBlueBg,
                  borderRadius: BorderRadius.circular(WSRadius.md),
                ),
                child: Row(children: [
                  const Icon(Icons.public_outlined,
                      size: 16, color: WSColors.glacierBlue),
                  const SizedBox(width: WSSpacing.sm),
                  Expanded(
                    child: Text(
                      'Partagée — tes corrections seront re-propagées '
                      'à la communauté à la sauvegarde.',
                      style: WSText.caption.copyWith(color: WSColors.glacierBlue),
                    ),
                  ),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _label(String txt) => Padding(
        padding: const EdgeInsets.only(bottom: WSSpacing.sm),
        child: Text(txt.toUpperCase(),
            style: WSText.micro.copyWith(color: WSColors.stoneGray)),
      );

  String _stabilityLabel(int s) {
    switch (s) {
      case 1: return '1 — Très stable, conditions sûres';
      case 2: return '2 — Stable';
      case 3: return '3 — Variable, prudence';
      case 4: return '4 — Instable, déclenchements probables';
      case 5: return '5 — Très instable, dangereux';
      default: return '';
    }
  }
}

// ─── Chip de sélection (type neige, orientation) ─────────────────────────────
class _SelectableChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? color; // couleur d'accent si fournie (= type neige)
  final VoidCallback onTap;

  const _SelectableChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final accent = color ?? WSColors.glacierBlue;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(WSRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: WSSpacing.md,
          vertical: WSSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected ? accent : WSColors.snowWhite,
          borderRadius: BorderRadius.circular(WSRadius.pill),
          border: Border.all(
            color: selected ? accent : WSColors.glacierMid,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (color != null && !selected) ...[
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                color: selected ? WSColors.snowWhite : WSColors.slateDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
