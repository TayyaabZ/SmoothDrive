import 'dart:async';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/road_hazard.dart';

class DatabaseService {
  DatabaseService._internal();

  static final DatabaseService _instance = DatabaseService._internal();

  factory DatabaseService() => _instance;

  Database? _database;
  final List<Map<String, dynamic>> _queue = [];
  Timer? _timer;
  bool _busy = false;

  Future<Database> _initDatabase() async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, 'smoothdrive.db');
    return openDatabase(
      path,
      version: 4,
      onCreate: (db, version) async {
        await db.execute(
          "CREATE TABLE hazards (id INTEGER PRIMARY KEY AUTOINCREMENT, lat REAL, lng REAL, timestamp TEXT, impactMagnitude REAL, hazard_type TEXT DEFAULT 'pothole')",
        );
        await db.execute(
          'CREATE TABLE sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, start_time TEXT, duration TEXT, hazard_count INTEGER, max_impact REAL, pothole_count INTEGER DEFAULT 0, speed_bump_count INTEGER DEFAULT 0)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'CREATE TABLE sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, start_time TEXT, duration TEXT, hazard_count INTEGER, max_impact REAL)',
          );
        }
        if (oldVersion < 3) {
          try {
            await db.execute(
              "ALTER TABLE hazards ADD COLUMN hazard_type TEXT DEFAULT 'pothole'",
            );
          } on DatabaseException {
            return;
          }
        }
        if (oldVersion < 4) {
          try {
            await db.execute(
              'ALTER TABLE sessions ADD COLUMN pothole_count INTEGER DEFAULT 0',
            );
            await db.execute(
              'ALTER TABLE sessions ADD COLUMN speed_bump_count INTEGER DEFAULT 0',
            );
          } on DatabaseException {
            return;
          }
        }
      },
    );
  }

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }
    _database = await _initDatabase();
    return _database!;
  }

  void _scheduleFlush() {
    _timer ??= Timer(const Duration(milliseconds: 500), () {
      _timer = null;
      _flush();
    });
  }

  Future<void> _flush() async {
    if (_busy || _queue.isEmpty) {
      return;
    }
    _busy = true;
    final items = List<Map<String, dynamic>>.from(_queue);
    _queue.clear();
    final db = await database;
    final batch = db.batch();
    for (final item in items) {
      batch.insert('hazards', item);
    }
    await batch.commit(noResult: true);
    _busy = false;
    if (_queue.isNotEmpty) {
      _scheduleFlush();
    }
  }

  Future<void> insertHazard(RoadHazard hazard) {
    _queue.add(hazard.toMap());
    if (_queue.length >= 20) {
      _flush();
    } else {
      _scheduleFlush();
    }
    return Future.value();
  }

  Future<List<RoadHazard>> getHazards() async {
    await _flush();
    final db = await database;
    final rows = await db.query('hazards');
    return rows.map((map) => RoadHazard.fromMap(map)).toList();
  }

  Future<void> insertSession(Map<String, dynamic> session) async {
    final db = await database;
    await db.insert('sessions', session);
  }

  Future<List<Map<String, dynamic>>> getSessions() async {
    final db = await database;
    return await db.query('sessions', orderBy: 'start_time DESC');
  }

  Future<void> clearHazards() async {
    _queue.clear();
    _timer?.cancel();
    _timer = null;
    final db = await database;
    await db.delete('hazards');
  }
}
