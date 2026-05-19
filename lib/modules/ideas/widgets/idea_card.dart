// lib/modules/ideas/widgets/idea_card.dart
//
// Card d'une idée affichée dans le carousel horizontal en bas de la carte.
// Compact : nom, score, météo, BERA, exposition, D+, difficulté.
// Tap → ouvre le détail complet (idea_detail_sheet).

import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../models/idea.dart';
import '../services/ideas_preferences.dart';

class IdeaCard extends StatelessWidget {
  final Idea idea;
  final int index;      // 1-based pour affichage
  final bool selected;
  final VoidCallback onTap;

  const IdeaCard({
    super.key,
    required this.idea,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  Color _beraColor(int? r) {
    switch (r) {
      case 1: return WSColors.powderGreen;
      case 2: return const Color(0xFFE8A93C);
      case 3: return WSColors.sunOrange;
      case 4: return WSColors.avalancheRed;
      case 5: return WSColors.slateDark;
      default: return WSColors.stoneGray;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.symmetric(horizontal: WSSpacing.xs),
        padding: const EdgeInsets.all(WSSpacing.md),
        decoration: BoxDecoration(
          color: WSColors.snowWhite.withOpacity(0.97),
          borderRadius: BorderRadius.circular(WSRadius.lg),
          border: Border.all(
            color: selected ? WSColors.glacierBlue : WSColors.glacierMid,
            width: selected ? 1.5 : 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(selected ? 0.10 : 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ligne 1 : numéro + nom
            Row(
              children: [
                Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    color: selected ? WSColors.glacierBlue : WSColors.glacierLight,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text('$index',
                    style: TextStyle(
                      color: selected ? WSColors.snowWhite : WSColors.slateDark,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    )),
                ),
                const SizedBox(width: WSSpacing.sm),
                Expanded(
                  child: Text(
                    idea.name,
                    style: WSText.body.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Actions rapides : wishlist + masquer. Observent les
                // préférences pour changer d'état en live au tap.
                _CardQuickActions(url: idea.url),
              ],
            ),
            const SizedBox(height: 6),
            // Massif + difficulté en sous-titre
            Text(
              '${idea.massif} · ${idea.difficulty}',
              style: WSText.micro.copyWith(color: WSColors.stoneGray),
            ),
            const SizedBox(height: WSSpacing.sm),
            // Ligne 3 : chips info (D+, expo, météo icône, BERA)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _MiniChip(
                  icon: Icons.trending_up,
                  text: '${idea.denivelePositif.round()} m',
                ),
                _MiniChip(
                  icon: Icons.explore_outlined,
                  text: idea.exposition,
                ),
                _MiniChip(
                  icon: null,
                  text: '${idea.meteo.icon} ${idea.meteo.meanTemp.round()}°',
                ),
                if (idea.bera.risque != null)
                  _MiniChip(
                    icon: Icons.warning_amber_outlined,
                    text: 'BERA ${idea.bera.risque}',
                    color: _beraColor(idea.bera.risque),
                  ),
              ],
            ),
            // Ligne IA si dispo
            if (idea.aiPicto != null && idea.aiQualite != null) ...[
              const SizedBox(height: WSSpacing.sm),
              Row(
                children: [
                  Text(idea.aiPicto!, style: const TextStyle(fontSize: 15)),
                  const SizedBox(width: 4),
                  Text(idea.aiQualite!,
                    style: WSText.caption.copyWith(
                      fontWeight: FontWeight.w600,
                    )),
                  const Spacer(),
                  if (idea.aiNote10 != null)
                    Text('${idea.aiNote10!.toStringAsFixed(1)}/10',
                      style: WSText.caption.copyWith(
                        color: WSColors.stoneGray,
                      )),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final IconData? icon;
  final String text;
  final Color? color;
  const _MiniChip({this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? WSColors.stoneGray;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: c.withOpacity(0.10),
        borderRadius: BorderRadius.circular(WSRadius.pill),
        border: Border.all(color: c.withOpacity(0.30), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: c),
            const SizedBox(width: 3),
          ],
          Text(text,
            style: WSText.micro.copyWith(
              color: c,
              fontWeight: FontWeight.w600,
            )),
        ],
      ),
    );
  }
}

/// Deux petites icônes en haut-droit de la card pour wishlist / masquer.
/// Observe IdeasPreferences pour rebuild en temps réel quand on tape.
class _CardQuickActions extends StatelessWidget {
  final String? url;
  const _CardQuickActions({required this.url});

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) return const SizedBox.shrink();
    final prefs = IdeasPreferences();
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) {
        final inWishlist = prefs.isInWishlist(url);
        final hidden     = prefs.isHidden(url);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Wishlist : étoile pleine si dans la liste, contour sinon.
            _IconButton28(
              icon: inWishlist ? Icons.star : Icons.star_border,
              color: inWishlist ? const Color(0xFFE8A93C) : WSColors.stoneGray,
              tooltip: inWishlist
                  ? 'Retirer de ma wish-list'
                  : 'Ajouter à ma wish-list',
              onTap: () {
                if (inWishlist) {
                  prefs.removeFromWishlist(url!);
                } else {
                  prefs.addToWishlist(url!);
                }
              },
            ),
            _IconButton28(
              icon: hidden
                  ? Icons.visibility_off
                  : Icons.visibility_off_outlined,
              color: hidden ? WSColors.avalancheRed : WSColors.stoneGray,
              tooltip: hidden ? 'Démasquer' : 'Masquer cette sortie',
              onTap: () {
                if (hidden) {
                  prefs.unhide(url!);
                } else {
                  prefs.hide(url!);
                }
              },
            ),
          ],
        );
      },
    );
  }
}

/// Petit bouton icône 28x28 — assez gros pour le mode gants tout en restant
/// discret en coin de card.
class _IconButton28 extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;
  const _IconButton28({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 20,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }
}
