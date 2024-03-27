import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:path_provider/path_provider.dart';

Future<Database> openDatabase(String filename) async {
  final dbPath = await getApplicationDocumentsDirectory();
  final db = sqlite3.open('${dbPath.path}/$filename.sqlite');
  migrate(db);
  return db;
}

void migrate(Database db) {
  db.execute('''
    CREATE TABLE IF NOT EXISTS accelerometer (
      timestamp INTEGER NOT NULL,
      x REAL NOT NULL,
      y REAL NOT NULL,
      z REAL NOT NULL
    )
  ''');
  db.execute('''
    CREATE TABLE IF NOT EXISTS gyroscope (
      timestamp INTEGER NOT NULL,
      x REAL NOT NULL,
      y REAL NOT NULL,
      z REAL NOT NULL
    )
  ''');
  db.execute('''
    CREATE TABLE IF NOT EXISTS gps (
      timestamp INTEGER NOT NULL,
      latitude REAL NOT NULL,
      longitude REAL NOT NULL,
      heading REAL NOT NULL,
      headingAccuracy REAL NOT NULL,
      speed REAL NOT NULL,
      speedAccuracy REAL NOT NULL
    )
  ''');

  db.execute(
      'CREATE INDEX IF NOT EXISTS accelerometer_timestamp ON accelerometer (timestamp)');
  db.execute(
      'CREATE INDEX IF NOT EXISTS gyroscope_timestamp ON gyroscope (timestamp)');
  db.execute('CREATE INDEX IF NOT EXISTS gps_timestamp ON gps (timestamp)');
}

void insertAccelerometerData(UserAccelerometerEvent event, Database db) {
  db.execute(
    'INSERT INTO accelerometer (timestamp, x, y, z) VALUES (?, ?, ?, ?)',
    [DateTime.now().millisecondsSinceEpoch, event.x, event.y, event.z],
  );
}

void insertGyroscopeData(GyroscopeEvent event, Database db) {
  db.execute(
    'INSERT INTO gyroscope (timestamp, x, y, z) VALUES (?, ?, ?, ?)',
    [DateTime.now().millisecondsSinceEpoch, event.x, event.y, event.z],
  );
}

void insertGpsData(Position event, Database db) {
  db.execute(
    'INSERT INTO gps (timestamp, latitude, longitude, heading, headingAccuracy, speed, speedAccuracy) VALUES (?, ?, ?, ?, ?, ?, ?)',
    [
      event.timestamp.millisecondsSinceEpoch,
      event.latitude,
      event.longitude,
      event.heading,
      event.headingAccuracy,
      event.speed,
      event.speedAccuracy
    ],
  );
}

class Range {
  final double min, max;

  const Range(this.min, this.max);
}

class MinMaxData {
  final Range timestamp,
      accelerometerX,
      accelerometerY,
      accelerometerZ,
      accelerometerMagnitude,
      gyroscopeX,
      gyroscopeY,
      gyroscopeZ,
      gyroscopeMagnitude,
      latitude,
      longitude;

  const MinMaxData({
    required this.timestamp,
    required this.accelerometerX,
    required this.accelerometerY,
    required this.accelerometerZ,
    required this.accelerometerMagnitude,
    required this.gyroscopeX,
    required this.gyroscopeY,
    required this.gyroscopeZ,
    required this.gyroscopeMagnitude,
    required this.latitude,
    required this.longitude,
  });
}

MinMaxData minMaxData(Database db) {
  final accelerometerData = db
      .select(
        'SELECT MIN(x) as minX, MAX(x) as maxX, MIN(y) as minY, MAX(y) as maxY, MIN(z) as minZ, MAX(z) as maxZ, MIN(x*x + y*y + z*z) as minMagnitude, MAX(x*x + y*y + z*z) as maxMagnitude FROM accelerometer',
      )
      .first;
  final gyroscopeData = db
      .select(
        'SELECT MIN(x) as minX, MAX(x) as maxX, MIN(y) as minY, MAX(y) as maxY, MIN(z) as minZ, MAX(z) as maxZ, MIN(x*x + y*y + z*z) as minMagnitude, MAX(x*x + y*y + z*z) as maxMagnitude FROM gyroscope',
      )
      .first;
  final gpsData = db
      .select(
        'SELECT MIN(latitude) as minLat, MAX(latitude) as maxLat, MIN(longitude) as minLon, MAX(longitude) as maxLon FROM gps',
      )
      .first;
  final timestampData = db.select(
    """
    SELECT MAX(minTimestamp) as min, MIN(maxTimestamp) as max FROM (
      SELECT MIN(timestamp) AS minTimestamp, MAX(timestamp) AS maxTimestamp FROM accelerometer
      UNION
      SELECT MIN(timestamp) AS minTimestamp, MAX(timestamp) AS maxTimestamp FROM gyroscope
      UNION
      SELECT MIN(timestamp) AS minTimestamp, MAX(timestamp) AS maxTimestamp FROM gps
    )""",
  ).first;
  return MinMaxData(
    timestamp: Range(
      (timestampData["min"] as int).toDouble(),
      (timestampData["max"] as int).toDouble(),
    ),
    accelerometerX: Range(accelerometerData["minX"], accelerometerData["maxX"]),
    accelerometerY: Range(accelerometerData["minY"], accelerometerData["maxY"]),
    accelerometerZ: Range(accelerometerData["minZ"], accelerometerData["maxZ"]),
    accelerometerMagnitude: Range(
      accelerometerData["minMagnitude"],
      accelerometerData["maxMagnitude"],
    ),
    gyroscopeX: Range(gyroscopeData["minX"], gyroscopeData["maxX"]),
    gyroscopeY: Range(gyroscopeData["minY"], gyroscopeData["maxY"]),
    gyroscopeZ: Range(gyroscopeData["minZ"], gyroscopeData["maxZ"]),
    gyroscopeMagnitude: Range(
      gyroscopeData["minMagnitude"],
      gyroscopeData["maxMagnitude"],
    ),
    latitude: Range(gpsData["minLat"], gpsData["maxLat"]),
    longitude: Range(gpsData["minLon"], gpsData["maxLon"]),
  );
}

class DataAtTime {
  final double timestamp,
      accelerometerX,
      accelerometerY,
      accelerometerZ,
      gyroscopeX,
      gyroscopeY,
      gyroscopeZ,
      latitude,
      longitude;

  DataAtTime({
    required this.timestamp,
    required this.accelerometerX,
    required this.accelerometerY,
    required this.accelerometerZ,
    required this.gyroscopeX,
    required this.gyroscopeY,
    required this.gyroscopeZ,
    required this.latitude,
    required this.longitude,
  });

  double get accelerometerMagnitude {
    return accelerometerX * accelerometerX +
        accelerometerY * accelerometerY +
        accelerometerZ * accelerometerZ;
  }

  double get gyroscopeMagnitude {
    return gyroscopeX * gyroscopeX +
        gyroscopeY * gyroscopeY +
        gyroscopeZ * gyroscopeZ;
  }
}

double lerp(double a, double b, double t) {
  return a + (b - a) * t;
}

DataAtTime dataAtTime(Database db, double timestamp) {
  final accBefore = db.select(
    'SELECT timestamp, x, y, z FROM accelerometer WHERE timestamp <= ? ORDER BY timestamp DESC LIMIT 1',
    [timestamp],
  ).first;
  final accAfter = db.select(
    'SELECT timestamp, x, y, z FROM accelerometer WHERE timestamp >= ? ORDER BY timestamp ASC LIMIT 1',
    [timestamp],
  ).first;
  final gyroBefore = db.select(
    'SELECT timestamp, x, y, z FROM gyroscope WHERE timestamp <= ? ORDER BY timestamp DESC LIMIT 1',
    [timestamp],
  ).first;
  final gyroAfter = db.select(
    'SELECT timestamp, x, y, z FROM gyroscope WHERE timestamp >= ? ORDER BY timestamp ASC LIMIT 1',
    [timestamp],
  ).first;
  final gpsBefore = db.select(
    'SELECT timestamp, latitude, longitude FROM gps WHERE timestamp <= ? ORDER BY timestamp DESC LIMIT 1',
    [timestamp],
  ).first;
  final gpsAfter = db.select(
    'SELECT timestamp, latitude, longitude FROM gps WHERE timestamp >= ? ORDER BY timestamp ASC LIMIT 1',
    [timestamp],
  ).first;
  return DataAtTime(
    timestamp: timestamp,
    accelerometerX: lerp(accBefore[1], accAfter[1],
        (timestamp - accBefore[0]) / (accAfter[0] - accBefore[0])),
    accelerometerY: lerp(accBefore[2], accAfter[2],
        (timestamp - accBefore[0]) / (accAfter[0] - accBefore[0])),
    accelerometerZ: lerp(accBefore[3], accAfter[3],
        (timestamp - accBefore[0]) / (accAfter[0] - accBefore[0])),
    gyroscopeX: lerp(gyroBefore[1], gyroAfter[1],
        (timestamp - gyroBefore[0]) / (gyroAfter[0] - gyroBefore[0])),
    gyroscopeY: lerp(gyroBefore[2], gyroAfter[2],
        (timestamp - gyroBefore[0]) / (gyroAfter[0] - gyroBefore[0])),
    gyroscopeZ: lerp(gyroBefore[3], gyroAfter[3],
        (timestamp - gyroBefore[0]) / (gyroAfter[0] - gyroBefore[0])),
    latitude: lerp(gpsBefore[1], gpsAfter[1],
        (timestamp - gpsBefore[0]) / (gpsAfter[0] - gpsBefore[0])),
    longitude: lerp(gpsBefore[2], gpsAfter[2],
        (timestamp - gpsBefore[0]) / (gpsAfter[0] - gpsBefore[0])),
  );
}
