// lib/modules/route/route_controller.dart

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../core/elevation/dem_selector.dart';
import '../../core/elevation/elevation_provider.dart';
import '../../core/routing/offline_route_provider.dart';
import '../../core/routing/route_enricher.dart';
import '../../core/routing/route_provider.dart';
import '../../shared/settings/user_profile.dart';
import '../time/time_controller.dart';

enum RoutePhase { idle, awaitingEnd, computing, ready, error }

/// Mode de saisie de l'itinéraire.
enum RouteMode {
  /// Routage automatique : tap A puis tap B → A* sur le graphe OSM.
  auto,
  /// Dessin libre : le doigt glisse sur la carte → polyline simplifiée.
  freehand,
}

class RouteController extends ChangeNotifier {
  static final RouteController _instance = RouteController._();
  factory RouteController() => _instance;
  RouteController._();

  final RouteProvider _router = OfflineRouteProvider();
  final UserProfile _userProfile = UserProfile();
  final TimeController _time = TimeController();

  // ── État ───────────────────────────────────────────────────────────────────
  RoutePhase _phase = RoutePhase.idle;
  RouteMode _mode = RouteMode.auto;
  LatLng? _start;
  LatLng? _end;
  RouteResult? _route;
  RouteStats? _stats;
  String? _message;

  // Points bruts du dessin libre (avant simplification).
  final List<LatLng> _freehandRaw = [];
  // Tracé en cours de dessin (simplifié à la volée pour l'affichage).
  List<LatLng> _freehandPreview = [];

  RoutePhase get phase => _phase;
  RouteMode get mode => _mode;
  LatLng? get start => _start;
  LatLng? get end => _end;
  List<LatLng> get tracePoints =>
      _phase == RoutePhase.idle && _freehandPreview.isNotEmpty
          ? _freehandPreview
          : (_route?.points ?? const []);
  RouteStats? get stats => _stats;
  String? get message => _message;
  bool get hasRoute => _route != null;
  bool get isDrawing =>
      _mode == RouteMode.freehand && _freehandRaw.isNotEmpty;

  // ── Mode ──────────────────────────────────────────────────────────────────

  void setMode(RouteMode m) {
    if (_mode == m) return;
    _mode = m;
    reset(keepMode: true);
  }

  // ── Interaction carte — mode Auto ─────────────────────────────────────────

  Future<void> onTap(LatLng p) async {
    if (_mode != RouteMode.auto) return;
    switch (_phase) {
      case RoutePhase.idle:
      case RoutePhase.ready:
      case RoutePhase.error:
        _start = p;
        _end = null;
        _route = null;
        _stats = null;
        _message = null;
        _phase = RoutePhase.awaitingEnd;
        notifyListeners();
        break;
      case RoutePhase.awaitingEnd:
        _end = p;
        await _computeAuto();
        break;
      case RoutePhase.computing:
        break;
    }
  }

  // ── Interaction carte — mode Main levée ───────────────────────────────────

  /// Appelé au début du geste de dessin (onPanStart).
  void onFreehandStart(LatLng p) {
    if (_mode != RouteMode.freehand) return;
    _freehandRaw.clear();
    _freehandPreview = [];
    _route = null;
    _stats = null;
    _message = null;
    _phase = RoutePhase.idle;
    _freehandRaw.add(p);
    notifyListeners();
  }

  /// Appelé à chaque point pendant le glissement (onPanUpdate).
  void onFreehandUpdate(LatLng p) {
    if (_mode != RouteMode.freehand) return;
    if (_freehandRaw.isEmpty) return;

    // N'ajoute le point que si on a bougé d'au moins 10m (évite l'accumulation
    // de points identiques sur les micro-tremblements).
    final last = _freehandRaw.last;
    final dist = _haversine(
        last.latitude, last.longitude, p.latitude, p.longitude);
    if (dist < 10.0) return;

    _freehandRaw.add(p);

    // Prévisualisation simplifiée (epsilon grossier pour la fluidité).
    if (_freehandRaw.length >= 3) {
      _freehandPreview = _douglasPeucker(_freehandRaw, 0.00008);
    } else {
      _freehandPreview = List.of(_freehandRaw);
    }
    notifyListeners();
  }

  /// Appelé quand le doigt se lève (onPanEnd).
  Future<void> onFreehandEnd() async {
    if (_mode != RouteMode.freehand) return;
    if (_freehandRaw.length < 2) {
      _freehandRaw.clear();
      _freehandPreview = [];
      notifyListeners();
      return;
    }
    await _computeFreehand();
  }

  // ── Calcul — mode Auto ────────────────────────────────────────────────────

  Future<void> _computeAuto() async {
    final s = _start, e = _end;
    if (s == null || e == null) return;

    _phase = RoutePhase.computing;
    _message = null;
    notifyListeners();

    final profile = routeProfileFrom(_userProfile);

    try {
      final route = await _router.route(s, e, profile);
      if (route == null) {
        _phase = RoutePhase.error;
        _message = 'Aucun itinéraire trouvé. '
            'Vérifie que les données de routage sont installées.';
        notifyListeners();
        return;
      }
      await _enrich(route);
    } catch (err, st) {
      _phase = RoutePhase.error;
      _message = 'Erreur de calcul : $err';
      debugPrint('Routing error: $err\n$st');
      notifyListeners();
    }
  }

  // ── Calcul — mode Main levée ──────────────────────────────────────────────

  Future<void> _computeFreehand() async {
    _phase = RoutePhase.computing;
    notifyListeners();

    try {
      // Simplification finale plus agressive (epsilon ~15m ≈ 0.000135°).
      final simplified = _douglasPeucker(_freehandRaw, 0.000135);
      if (simplified.length < 2) {
        _phase = RoutePhase.error;
        _message = 'Tracé trop court.';
        notifyListeners();
        return;
      }

      _start = simplified.first;
      _end = simplified.last;

      // On construit un RouteResult synthétique à partir de la polyline libre.
      // La distance est calculée segment par segment.
      double dist = 0;
      for (int i = 1; i < simplified.length; i++) {
        dist += _haversine(
          simplified[i - 1].latitude, simplified[i - 1].longitude,
          simplified[i].latitude, simplified[i].longitude,
        );
      }
      final syntheticRoute = RouteResult(
        points: simplified,
        distanceM: dist,
        snapDistanceM: 0,
      );
      await _enrich(syntheticRoute);
    } catch (err, st) {
      _phase = RoutePhase.error;
      _message = 'Erreur de calcul : $err';
      debugPrint('Freehand error: $err\n$st');
      notifyListeners();
    } finally {
      _freehandRaw.clear();
      _freehandPreview = [];
    }
  }

  // ── Enrichissement commun ─────────────────────────────────────────────────

  Future<void> _enrich(RouteResult route) async {
    final dem = await _selectDem(route);
    final enricher = RouteEnricher(dem: dem, munter: _time.munter);
    final profile = routeProfileFrom(_userProfile);
    final stats = await enricher.enrich(route, profile);

    _route = route;
    _stats = stats;
    _phase = RoutePhase.ready;

    if (route.snapDistanceM > 150) {
      _message = 'Raccordé au chemin le plus proche '
          '(${route.snapDistanceM.round()} m).';
    }
    notifyListeners();
  }

  Future<ElevationProvider> _selectDem(RouteResult route) async {
    var minLat = 90.0, maxLat = -90.0, minLng = 180.0, maxLng = -180.0;
    for (final p in route.points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    final selection = await DemSelector.select(
      center: route.points.first,
      prefetchSw: LatLng(minLat, minLng),
      prefetchNe: LatLng(maxLat, maxLng),
    );
    return selection.provider;
  }

  // ── Reset ─────────────────────────────────────────────────────────────────

  void reset({bool keepMode = false}) {
    _phase = RoutePhase.idle;
    _start = null;
    _end = null;
    _route = null;
    _stats = null;
    _message = null;
    _freehandRaw.clear();
    _freehandPreview = [];
    if (!keepMode) _mode = RouteMode.auto;
    notifyListeners();
  }

  // ── Douglas-Peucker ───────────────────────────────────────────────────────
  //
  // Epsilon en degrés (~0.000135° ≈ 15m, ~0.00008° ≈ 9m pour la preview).

  static List<LatLng> _douglasPeucker(List<LatLng> pts, double epsilon) {
    if (pts.length < 3) return pts;
    double dmax = 0;
    int idx = 0;
    final a = pts.first;
    final b = pts.last;
    for (int i = 1; i < pts.length - 1; i++) {
      final d = _perpDistance(pts[i], a, b);
      if (d > dmax) { dmax = d; idx = i; }
    }
    if (dmax > epsilon) {
      final left  = _douglasPeucker(pts.sublist(0, idx + 1), epsilon);
      final right = _douglasPeucker(pts.sublist(idx), epsilon);
      return [...left.sublist(0, left.length - 1), ...right];
    }
    return [a, b];
  }

  static double _perpDistance(LatLng p, LatLng a, LatLng b) {
    final dx = b.longitude - a.longitude;
    final dy = b.latitude  - a.latitude;
    if (dx == 0 && dy == 0) {
      return math.sqrt(
        (p.longitude - a.longitude) * (p.longitude - a.longitude) +
        (p.latitude  - a.latitude)  * (p.latitude  - a.latitude),
      );
    }
    final t = ((p.longitude - a.longitude) * dx +
               (p.latitude  - a.latitude)  * dy) /
              (dx * dx + dy * dy);
    final px = a.longitude + t * dx;
    final py = a.latitude  + t * dy;
    return math.sqrt(
      (p.longitude - px) * (p.longitude - px) +
      (p.latitude  - py) * (p.latitude  - py),
    );
  }

  static double _haversine(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}
