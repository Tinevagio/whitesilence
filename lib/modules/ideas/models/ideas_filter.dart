// lib/modules/ideas/models/ideas_filter.dart
//
// Filtres saisis par l'utilisateur dans la bottom sheet.
// Reflète les query params de GET /ideas.

class IdeasFilter {
  final DateTime date;
  final String niveau;                // "S1".."S5"
  final int dplusMin;
  final int dplusMax;
  final Set<String> expositions;      // sous-ensemble de {N,NE,E,SE,S,SO,O,NO}
  final Set<String> massifs;          // vide = tous
  final int nResults;
  /// Inclure le score IA (modèle LightGBM) dans la réponse.
  /// Désactivé par défaut car ça multiplie le temps de calcul par ~2 sur le
  /// backend Render free tier. L'utilisateur peut l'activer dans la sheet
  /// de filtres s'il veut le détail qualité neige IA.
  final bool includeAi;
  /// Afficher aussi les sorties que l'utilisateur a masquées localement.
  /// Par défaut on les filtre (c'est l'intérêt de masquer). L'utilisateur
  /// peut le toggle dans la sheet de filtres s'il veut revoir l'ensemble
  /// (et éventuellement démasquer une sortie).
  final bool showHidden;

  const IdeasFilter({
    required this.date,
    this.niveau = 'S3',
    this.dplusMin = 800,
    this.dplusMax = 1500,
    this.expositions = const {'N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO'},
    this.massifs = const {},
    this.nResults = 5,
    this.includeAi = false,
    this.showHidden = false,
  });

  IdeasFilter copyWith({
    DateTime? date,
    String? niveau,
    int? dplusMin,
    int? dplusMax,
    Set<String>? expositions,
    Set<String>? massifs,
    int? nResults,
    bool? includeAi,
    bool? showHidden,
  }) => IdeasFilter(
        date:       date ?? this.date,
        niveau:     niveau ?? this.niveau,
        dplusMin:   dplusMin ?? this.dplusMin,
        dplusMax:   dplusMax ?? this.dplusMax,
        expositions: expositions ?? this.expositions,
        massifs:    massifs ?? this.massifs,
        nResults:   nResults ?? this.nResults,
        includeAi:  includeAi ?? this.includeAi,
        showHidden: showHidden ?? this.showHidden,
      );

  /// Représentation textuelle compacte pour le header replié du panel :
  /// "S3 · 800-1500m · 5 idées"
  String get compactSummary {
    final parts = <String>[
      niveau,
      '${dplusMin}-${dplusMax}m',
      '$nResults idées',
    ];
    if (massifs.isNotEmpty && massifs.length <= 3) {
      parts.add(massifs.join(','));
    } else if (massifs.isNotEmpty) {
      parts.add('${massifs.length} massifs');
    }
    return parts.join(' · ');
  }
}
