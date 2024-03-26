import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';

class StartButton extends StatefulWidget {
  const StartButton({super.key});

  @override
  _StartButtonState createState() => _StartButtonState();
}

class _StartButtonState extends State<StartButton> {
  late StreamSubscription<UserAccelerometerEvent> accStream;
  late StreamSubscription<GyroscopeEvent> gyroStream;
  late StreamSubscription<Position> geoStream;

  bool isListening = false;

  void startListeningAccelerometer() async {
    await ensurePermissions();

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    accStream = await recordStream(
        userAccelerometerEventStream(
            samplingPeriod: SensorInterval.normalInterval),
        '$timestamp',
        'acc.txt');
    gyroStream =
        await recordStream(gyroscopeEventStream(), '$timestamp', 'gyro.txt');
    geoStream = await recordStream(
        Geolocator.getPositionStream(), '$timestamp', 'geo.txt');
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TextButton(
        onPressed: () {
          print("klik");
          setState(() {
            if (!isListening) {
              startListeningAccelerometer();
            } else {
              stopListening();
            }
            isListening = !isListening;
          });
        },
        child: Text(isListening ? "Stop" : "Start"),
      ),
      TextButton(
          onPressed: () {
            readData();
          },
          child: const Text("Read"))
    ]);
  }

  void stopListening() {
    accStream.cancel();
    gyroStream.cancel();
    geoStream.cancel();
  }

  Future<void> readData() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory(docsDir.path);
    final files = dir.listSync();
    for (final file in files) {
      final stat = file.statSync();
      if (stat.type != FileSystemEntityType.directory) continue;
      final files = Directory(file.path).listSync();
      for (final file in files) {
        final content = File(file.path).readAsStringSync();
        print("File: ${file.path}");
        print(content);
      }
    }
  }
}

Future<void> ensurePermissions() async {
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      // Permissions are denied, next time you could try
      // requesting permissions again (this is also where
      // Android's shouldShowRequestPermissionRationale
      // returned true. According to Android guidelines
      // your App should show an explanatory UI now.
      return Future.error('Location permissions are denied');
    }
  }
}

Future<StreamSubscription<T>> recordStream<T>(
    Stream<T> stream, String folder, String filename) async {
  final docsDir = await getApplicationDocumentsDirectory();
  final dir = Directory('${docsDir.path}/$folder');
  await dir.create();
  final file = File('${dir.path}/$filename');
  return stream.listen((event) {
    final now = DateTime.now().millisecondsSinceEpoch;
    file.writeAsStringSync('$now|$event\n', mode: FileMode.append);
  });
}
