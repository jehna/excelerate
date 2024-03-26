import 'package:excelerate/db.dart';
import 'package:flutter/material.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

class DetailsPage extends StatefulWidget {
  final String dbPath;

  const DetailsPage({super.key, required this.dbPath});

  @override
  _DeatilsPageState createState() => _DeatilsPageState();
}

const int NUM_POINTS = 200;

class _DeatilsPageState extends State<DetailsPage> {
  double position = 0.5;
  double size = 0.5;
  bool showGpsData = false;
  late sql.Database db;
  late MinMaxData minMax;

  @override
  void initState() {
    super.initState();
    db = sql.sqlite3.open(widget.dbPath, mode: sql.OpenMode.readOnly);
    minMax = minMaxData(db);
  }

  Iterable<GraphData> getGraphData() sync* {
    final timestampRange = (minMax.timestamp.max - minMax.timestamp.min) * size;
    final timestampPadding =
        (minMax.timestamp.max - minMax.timestamp.min - timestampRange) *
            position;
    final adjustedTimestampRange = Range(
        minMax.timestamp.min + timestampPadding,
        minMax.timestamp.min + timestampPadding + timestampRange);
    for (var i = 0; i < NUM_POINTS; i++) {
      final timestamp = minMax.timestamp.min +
          timestampPadding +
          timestampRange * i / NUM_POINTS;
      final data = dataAtTime(db, timestamp);
      yield showGpsData
          ? GraphData(
              normalize(
                  data.accelerometerMagnitude, minMax.accelerometerMagnitude),
              normalize(data.latitude, minMax.latitude),
              normalize(data.longitude, minMax.longitude),
              normalize(data.accelerometerX, minMax.accelerometerX),
            )
          : GraphData(
              normalize(
                  data.accelerometerMagnitude, minMax.accelerometerMagnitude),
              normalize(data.timestamp, adjustedTimestampRange),
              normalize(data.gyroscopeMagnitude, minMax.gyroscopeMagnitude),
              normalize(data.accelerometerX, minMax.accelerometerX),
            );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(
            'Deatils of ${widget.dbPath.split('/').last.split('.').first}'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 9,
            child: Container(
                padding: const EdgeInsets.all(20),
                color: Colors.black,
                child: CustomPaint(
                    painter: GraphPainter(getGraphData().toList()))),
          ),
          Expanded(
            flex: 1,
            child: Slider(
              value: position,
              onChanged: (value) {
                setState(() {
                  position = value;
                });
              },
            ),
          ),
          Expanded(
            flex: 1,
            child: Row(
              children: [
                Expanded(
                  child: Slider(
                    value: size,
                    onChanged: (value) {
                      setState(() {
                        size = value;
                      });
                    },
                  ),
                ),
                Switch(
                  value: showGpsData,
                  onChanged: (value) {
                    setState(() {
                      showGpsData = value;
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20)
        ],
      ),
    );
  }
}

class GraphData {
  final double color;
  final double x;
  final double y;
  final double size;

  const GraphData(this.color, this.x, this.y, this.size);
}

class GraphPainter extends CustomPainter {
  final List<GraphData> data;

  const GraphPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5
      ..strokeJoin = StrokeJoin.round;
    canvas.drawRect(
        Rect.fromLTWH(-size.width / 2, 0, 100, 100),
        Paint()
          ..color = Colors.black
          ..style = PaintingStyle.fill);

    for (int i = 1; i < data.length; i++) {
      final from = data[i - 1];
      final to = data[i];
      final percentDone = i / data.length;
      paint.color =
          HSVColor.fromAHSV(1, 100 - to.color * 100, 1, percentDone).toColor();
      paint.strokeWidth = 2 + to.size * 30;
      canvas.drawLine(Offset(from.x * size.width, from.y * size.height),
          Offset(to.x * size.width, to.y * size.height), paint);
    }
  }

  @override
  bool shouldRepaint(GraphPainter oldDelegate) => oldDelegate.data != data;
}

double normalize(double value, Range range) {
  return (value - range.min) / (range.max - range.min);
}
