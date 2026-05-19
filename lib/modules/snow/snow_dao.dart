// lib/modules/snow/snow_dao.dart
//
// Accès SQLite aux observations.
// Utilise la base globale WSDatabase.

import 'package:sqflite/sqflite.dart';

import '../../core/storage/db.dart';
import 'models/observation.dart';

class SnowDao {
  static const _table = 'observations';

  Future<void> save(Observation obs) async {
    final db = await WSDatabase.instance();
    await db.insert(_table, obs.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> update(Observation obs) async {
    final db = await WSDatabase.instance();
    await db.update(_table, obs.toMap(),
        where: 'id = ?', whereArgs: [obs.id]);
  }

  Future<void> delete(String id) async {
    final db = await WSDatabase.instance();
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  /// Toutes les observations, plus récentes en premier.
  Future<List<Observation>> loadAll() async {
    final db = await WSDatabase.instance();
    final rows = await db.query(_table, orderBy: 'timestamp DESC');
    return rows.map(Observation.fromMap).toList();
  }

  /// Observations de la session courante (= dernières 24h par défaut).
  /// Ordre chronologique croissant pour le récap fin de sortie.
  Future<List<Observation>> loadSession({Duration window = const Duration(hours: 24)}) async {
    final db = await WSDatabase.instance();
    final since = DateTime.now().subtract(window).toIso8601String();
    final rows = await db.query(
      _table,
      where: 'timestamp > ?',
      whereArgs: [since],
      orderBy: 'timestamp ASC',
    );
    return rows.map(Observation.fromMap).toList();
  }

  /// Observations qui n'ont jamais été uploadées Supabase.
  Future<List<Observation>> loadPending() async {
    final db = await WSDatabase.instance();
    final rows = await db.query(
      _table,
      where: 'uploaded = 0',
      orderBy: 'timestamp ASC',
    );
    return rows.map(Observation.fromMap).toList();
  }

  /// Force le flag uploaded sur toutes les obs — utile pour éviter le réupload
  /// d'observations historiques au premier démarrage du module.
  Future<void> markAllAsUploaded() async {
    final db = await WSDatabase.instance();
    await db.update(_table, {'uploaded': 1});
  }

  Future<void> clearAll() async {
    final db = await WSDatabase.instance();
    await db.delete(_table);
  }
}
