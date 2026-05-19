// lib/modules/ideas/widgets/idea_pin.dart
//
// Pin numéroté pour une idée sur la carte. Le pin sélectionné est plus gros
// + couleur de marque, les autres en gris glacier.

import 'package:flutter/material.dart';

import '../../../core/theme/colors.dart';

class IdeaPin extends StatelessWidget {
  final int index;       // 1-based pour l'affichage
  final bool selected;
  final VoidCallback onTap;

  const IdeaPin({
    super.key,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final size = selected ? 38.0 : 28.0;
    final color = selected ? WSColors.glacierBlue : WSColors.snowWhite;
    final textColor = selected ? WSColors.snowWhite : WSColors.slateDark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width:  size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? WSColors.glacierBlue : WSColors.glacierMid,
            width: selected ? 2 : 1.2,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: WSColors.glacierBlue.withOpacity(0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          '$index',
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w700,
            fontSize: selected ? 16 : 13,
          ),
        ),
      ),
    );
  }
}
