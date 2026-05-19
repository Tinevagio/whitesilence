// lib/modules/conditions/services/snow_interpolation.dart
//
// Interpolation de l'enneigement (cm de neige au sol) pour un point donné
// selon son altitude et son exposition, en utilisant les niveaux BERA de
// la sortie /conditions.
//
// Port direct du JS du frontend V7 (fonction `interpolateSnow`).

import '../models/bera_info.dart';
import '../models/point_conditions.dart';

class SnowInterpolation {
  SnowInterpolation._();

  /// Retourne l'enneigement estimé en cm pour ce point, ou null si le BERA
  /// n'a pas de niveaux d'enneigement renseignés.
  ///
  /// Logique :
  ///   - Si le point est dans la plage de deux niveaux BERA : interpolation
  ///     linéaire entre les deux.
  ///   - Si au-dessus du dernier niveau : extrapolation +5cm/100m.
  ///   - Si en-dessous du premier niveau : interpolation vers la limite
  ///     d'enneigement (0 si plus bas que la limite).
  static double? interpolate(PointConditions pt) {
    final bera = pt.bera;
    if (bera == null) return null;
    final niveaux = bera.enneigementNiveaux;
    if (niveaux == null || niveaux.isEmpty) return null;

    final elev = pt.elevationM;
    final asp  = pt.aspectDeg;
    // Versant Nord = orienté vers la moitié supérieure du cercle trigo.
    // Note : on garde la convention du frontend (asp <= 90 || asp >= 270).
    // Cette convention reste valable même avec le bug Est/Ouest car les
    // hémisphères N/S sont symétriques par rapport à l'axe E-O inversé.
    final isNorth = asp <= 90 || asp >= 270;

    // ── 1. Interpolation entre deux niveaux ─────────────────────────────────
    for (int i = 0; i < niveaux.length - 1; i++) {
      final lo = niveaux[i];
      final hi = niveaux[i + 1];
      if (elev >= lo.alti && elev <= hi.alti) {
        final tt = (elev - lo.alti) / (hi.alti - lo.alti);
        final vLo = (isNorth ? lo.nCm : lo.sCm)
                 ?? (isNorth ? lo.sCm : lo.nCm) ?? 0;
        final vHi = (isNorth ? hi.nCm : hi.sCm)
                 ?? (isNorth ? hi.sCm : hi.nCm) ?? 0;
        return vLo + tt * (vHi - vLo);
      }
    }

    // ── 2. Extrapolation au-dessus du dernier niveau (+5cm/100m) ───────────
    final last = niveaux.last;
    if (elev > last.alti) {
      final extra = (elev - last.alti) * 0.05;
      final v = (isNorth ? last.nCm : last.sCm) ?? 0;
      return v + extra;
    }

    // ── 3. En-dessous du premier niveau : interpolation vers la limite ─────
    final first = niveaux.first;
    final lim   = (isNorth ? bera.limiteNordM : bera.limiteSudM) ?? first.alti;
    if (elev < lim) return 0;
    final denom = (first.alti - lim).abs().clamp(1, double.infinity);
    final tt = ((elev - lim) / denom).clamp(0.0, 1.0);
    final v = (isNorth ? first.nCm : first.sCm) ?? 0;
    return tt * v;
  }
}
