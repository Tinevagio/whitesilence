// lib/core/storage/db.dart
//
// Base de données SQLite globale WhiteSilence.
//
// Une seule base `whitesilence.db` partagée par tous les modules :
//   - table `observations` (module Neige)
//   - plus tard : table `tours` (module Sortie, Phase 5), table `trace_points`
//
// Schéma versionné via `version` + `onUpgrade` pour permettre les migrations
// futures sans perdre les données utilisateur.

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class WSDatabase {
  static const _dbName = 'whitesilence.db';
  static const _dbVersion = 2; // v2 : ajout table conditions_cache (Phase 3)

  static Database? _db;

  /// Singleton : la base est ouverte au premier appel et réutilisée ensuite.
  static Future<Database> instance() async {
    return _db ??= await _open();
  }

  static Future<Database> _open() async {
    final dir  = await getDatabasesPath();
    final path = join(dir, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    // Table observations — module Neige (créée en v1)
    await db.execute('''
      CREATE TABLE observations (
        id              TEXT PRIMARY KEY,
        lat             REAL    NOT NULL,
        lon             REAL    NOT NULL,
        altitude_m      REAL,
        timestamp       TEXT    NOT NULL,
        audio_path      TEXT,
        transcript      TEXT,
        snow_type       TEXT,
        depth_cm        INTEGER,
        stability_score INTEGER,
        aspect          TEXT,
        raw_notes       TEXT,
        uploaded        INTEGER DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_obs_timestamp ON observations(timestamp DESC)',
    );

    // Table conditions_cache — module Conditions (créée en v2)
    await _createConditionsCacheTable(db);
  }

  static Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    if (oldV < 2) {
      await _createConditionsCacheTable(db);
    }
    // Futures migrations : if (oldV < 3) { ... }
  }

  /// Schéma de la table de cache des conditions Névé.
  /// La clé `cache_key` encode bbox|date|resolution.
  /// `payload` contient le JSON brut de l'API.
  static Future<void> _createConditionsCacheTable(Database db) async {
    await db.execute('''
      CREATE TABLE conditions_cache (
        cache_key  TEXT PRIMARY KEY,
        fetched_at TEXT NOT NULL,
        payload    TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_cache_fetched ON conditions_cache(fetched_at DESC)',
    );
  }

  /// Pour les tests : ferme la base et la rouvre à la prochaine demande.
  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
