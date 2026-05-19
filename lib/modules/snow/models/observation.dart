// lib/modules/snow/models/observation.dart
//
// Observation nivologique. Migré depuis Hey Snowy.
// Le seul changement notable : `altitudeM` est nullable (au cas où le GPS
// n'a pas pu fournir l'altitude — ça arrive régulièrement).

import 'package:latlong2/latlong.dart';

/// Types de neige reconnus par l'IA (cf. ai_service.dart pour la liste maître).
class SnowTypes {
  SnowTypes._();
  static const poudre   = 'poudre';
  static const moquette = 'moquette';
  static const beton    = 'béton';
  static const transfo  = 'transfo';
  static const croute   = 'croûte';
  static const ventee   = 'ventée';
  static const humide   = 'humide';
  static const purge    = 'purge';
  static const lourde   = 'lourde';
  static const autre    = 'autre';
}

class Observation {
  final String id;
  final double lat;
  final double lon;
  final double? altitudeM;
  final DateTime timestamp;
  final String audioPath;
  String? transcript;
  String? snowType;
  int? depthCm;
  int? stabilityScore;
  String? aspect;
  String? rawNotes;
  bool uploaded;

  Observation({
    required this.id,
    required this.lat,
    required this.lon,
    required this.altitudeM,
    required this.timestamp,
    required this.audioPath,
    this.transcript,
    this.snowType,
    this.depthCm,
    this.stabilityScore,
    this.aspect,
    this.rawNotes,
    this.uploaded = false,
  });

  LatLng get latLng => LatLng(lat, lon);

  Map<String, dynamic> toMap() => {
        'id':              id,
        'lat':             lat,
        'lon':             lon,
        'altitude_m':      altitudeM,
        'timestamp':       timestamp.toIso8601String(),
        'audio_path':      audioPath,
        'transcript':      transcript,
        'snow_type':       snowType,
        'depth_cm':        depthCm,
        'stability_score': stabilityScore,
        'aspect':          aspect,
        'raw_notes':       rawNotes,
        'uploaded':        uploaded ? 1 : 0,
      };

  factory Observation.fromMap(Map<String, dynamic> m) => Observation(
        id:         m['id'],
        lat:        (m['lat'] as num).toDouble(),
        lon:        (m['lon'] as num).toDouble(),
        altitudeM:  (m['altitude_m'] as num?)?.toDouble(),
        timestamp:  DateTime.parse(m['timestamp']),
        audioPath:  m['audio_path'] ?? '',
        transcript: m['transcript'],
        snowType:   m['snow_type'],
        depthCm:    m['depth_cm'],
        stabilityScore: m['stability_score'],
        aspect:     m['aspect'],
        rawNotes:   m['raw_notes'],
        uploaded:   (m['uploaded'] ?? 0) == 1,
      );

  bool get isEnriched => snowType != null;

  @override
  String toString() =>
      'Observation($id, $lat/$lon, ${altitudeM ?? "?"}m, $snowType)';
}
