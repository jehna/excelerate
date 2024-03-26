import 'dart:async';
import 'dart:io';
import 'package:excelerate/db.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sqlite3/sqlite3.dart';

class StartButton extends StatefulWidget {
  const StartButton({super.key});

  @override
  _StartButtonState createState() => _StartButtonState();
}

enum AppState { stopped, started, starting }

class _StartButtonState extends State<StartButton> {
  late StreamSubscription<UserAccelerometerEvent> accStream;
  late StreamSubscription<GyroscopeEvent> gyroStream;
  late StreamSubscription<Position> geoStream;

  AppState state = AppState.stopped;
  List<String> fileList = [];

  @override
  void initState() {
    super.initState();
    refreshFileList();
  }

  void startListeningAccelerometer() async {
    setState(() {
      state = AppState.starting;
    });
    await ensurePermissions();
    final start = DateTime.now();
    final db = await openDatabase('${start.millisecondsSinceEpoch}');

    accStream = userAccelerometerEventStream()
        .listen((event) => insertAccelerometerData(event, db));
    gyroStream = gyroscopeEventStream()
        .listen((event) => insertGyroscopeData(event, db));
    geoStream = Geolocator.getPositionStream()
        .skipWhile((_) =>
            DateTime.now().difference(start) < const Duration(seconds: 10))
        .listen((event) => insertGpsData(event, db));

    await Future.delayed(const Duration(seconds: 10));
    setState(() {
      state = AppState.started;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisAlignment: MainAxisAlignment.start, children: [
      const SizedBox(height: 20),
      Image.asset('assets/car.png', height: 120),
      const SizedBox(height: 20),
      TextButton(
        style: TextButton.styleFrom(
          minimumSize: const Size(150, 150),
          backgroundColor: state == AppState.started
              ? Colors.red[800]
              : state == AppState.stopped
                  ? Colors.green[800]
                  : Colors.orange,
        ),
        onPressed: () {
          setState(() {
            if (state == AppState.stopped) {
              startListeningAccelerometer();
            } else if (state == AppState.started) {
              stopListening();
              refreshFileList();
              setState(() {
                state = AppState.stopped;
              });
            }
          });
        },
        child: Text(
            state == AppState.started
                ? "Stop"
                : state == AppState.stopped
                    ? "Start"
                    : "Starting",
            style: const TextStyle(fontSize: 30)),
      ),
      const SizedBox(height: 20),
      Expanded(
        flex: 1,
        child: SingleChildScrollView(
          child: ListView(shrinkWrap: true, children: [
            for (final file in fileList)
              GestureDetector(
                onTap: () {
                  Navigator.pushNamed(context, '/details', arguments: file);
                },
                child: Container(
                  color: Colors.grey[800],
                  margin: const EdgeInsets.all(3),
                  child: ListTile(
                    title: Text(file.split('/').last.split('.').first),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      style: ButtonStyle(
                          backgroundColor:
                              MaterialStateProperty.all(Colors.red),
                          foregroundColor:
                              MaterialStateProperty.all(Colors.white)),
                      onPressed: () {
                        File(file).delete();
                        refreshFileList();
                      },
                    ),
                  ),
                ),
              )
          ]),
        ),
      ),
      const SizedBox(height: 50)
    ]);
  }

  void stopListening() {
    accStream.cancel();
    gyroStream.cancel();
    geoStream.cancel();
  }

  Future<void> refreshFileList() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory(docsDir.path);
    final files = dir.listSync();

    setState(() {
      fileList = files
          .where((file) => file.path.endsWith('.sqlite'))
          .map((file) => file.path)
          .toList();
    });
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
