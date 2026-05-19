import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../module_registry.dart';

/// Contrat qu'un module respecte pour s'afficher sur la MapScreen.
///
/// Chaque module fournit zéro ou plusieurs `Widget` qui seront empilés dans
/// le `FlutterMap` (children), plus éventuellement un panneau affiché quand
/// l'utilisateur active le module via la bottom bar.
///
/// Les overlays sont des [Listenable] : la WSMapScreen s'y abonne pour
/// rebuild quand l'état change (notamment `interactionOptions`).
abstract class MapModuleOverlay extends ChangeNotifier {
  ModuleId get id;

  /// Layers à ajouter au FlutterMap (PolygonLayer, MarkerLayer, etc.).
  /// Ordre = ordre de rendu (les premiers sont en dessous).
  List<Widget> buildMapLayers(BuildContext context);

  /// Panneau d'action affiché en bas quand ce module est sélectionné.
  /// Retourne null pour un module passif (juste un overlay carte).
  Widget? buildActionPanel(BuildContext context) => null;

  /// Contenu additionnel affiché EN-DESSOUS de l'action panel (mais au-dessus
  /// de la bottom bar de navigation). Conçu pour les carrousels horizontaux
  /// de cards (ex: module Idées). Retourne null par défaut.
  Widget? buildBottomSheet(BuildContext context) => null;

  /// Widget affiché EN HAUT de la carte, juste sous le bandeau de navigation
  /// (logo WS + chip module + bouton GPS). Utile pour des contrôles toujours
  /// visibles qui ne doivent pas se trouver dans l'action panel (ex: slider
  /// d'heure du module Conditions, qu'on sort du panel pour éviter que le
  /// doigt dérape pendant le drag).
  /// Retourne null par défaut.
  Widget? buildTopChrome(BuildContext context) => null;

  /// Appelé quand l'utilisateur tape sur la carte alors que ce module est actif.
  /// [tapPosition] donne les coordonnées en pixels, [latLng] le point géographique.
  /// Retourne true pour intercepter le tap (empêcher les autres modules de réagir).
  bool onMapTap(BuildContext context, TapPosition tapPosition, LatLng latLng) =>
      false;

  /// Appelé sur appui long sur la carte. Même signature que onMapTap.
  /// Convention WhiteSilence : le long-press pose une "épingle" — pour le
  /// module time c'est un nouveau point d'origine, pour d'autres modules ce
  /// sera autre chose (ex: début d'enregistrement de trace).
  bool onMapLongPress(BuildContext context, TapPosition tapPosition, LatLng latLng) =>
      false;

  /// Si non-null, la WSMapScreen applique ces options à la carte au lieu des
  /// options par défaut. Permet aux overlays de désactiver temporairement le
  /// pan/zoom (ex : mode dessin de bbox dans le module Conditions).
  InteractionOptions? get interactionOptions => null;

  /// Si non-null, la WSMapScreen installe un GestureDetector au-dessus de la
  /// carte qui route les pan events vers cet handler. Utile pour dessiner
  /// une bbox au drag.
  MapDragHandler? get dragHandler => null;
}

/// Handler de drag pour les modes "dessin" (bbox, polygone…).
/// Les méthodes reçoivent les coordonnées géographiques converties par la
/// WSMapScreen depuis la position pixel via le MapController.
abstract class MapDragHandler {
  void onDragStart(LatLng start);
  void onDragUpdate(LatLng current);
  void onDragEnd(LatLng end);
}
