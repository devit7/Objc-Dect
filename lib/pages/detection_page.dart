import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import 'package:ultralytics_yolo/yolo_model.dart';

class DetectionPage extends StatefulWidget {
  const DetectionPage({Key? key}) : super(key: key);
  @override
  State<DetectionPage> createState() => _DetectionPageState();
}

class _DetectionPageState extends State<DetectionPage> {
  // Variable untuk menyimpan widget yang ditampilkan
  Widget currentView = Center(
    child: ElevatedButton(
      onPressed: null, // Placeholder (akan diperbaiki di constructor)
      child: Text('START YOLO'),
    ),
  );

  @override
  void initState() {
    super.initState();
    // Update currentView dengan tombol yang memiliki aksi
    currentView = Center(
      child: ElevatedButton(
        onPressed: switchView, // Panggil switchView saat tombol ditekan
        child: Text('START YOLO'),
      ),
    );
  }

  void switchView() {
    // Mengubah widget yang ditampilkan
    setState(() {
      currentView = YoloRealTimeView(onStop: () {
        setState(() {
          currentView = Center(
            child: ElevatedButton(
              onPressed: switchView,
              child: Text('START YOLO'),
            ),
          );
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: currentView,
      ),
    );
  }
}

class YoloRealTimeView extends StatefulWidget {
  final VoidCallback onStop;

  const YoloRealTimeView({Key? key, required this.onStop}) : super(key: key);

  @override
  _YoloRealTimeViewState createState() => _YoloRealTimeViewState();
}

class _YoloRealTimeViewState extends State<YoloRealTimeView> {
  final controller = UltralyticsYoloCameraController();
  final FlutterTts flutterTts = FlutterTts();
  List<String> detectedObjects = [];
  bool isSpeaking = false; // Untuk mencegah overlapping suara
  Timer? speechTimer;
  int lastSpeakTime = DateTime.now().millisecondsSinceEpoch;
  int currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _initializeTts();
    startSpeech();
  }

  void _initializeTts() async {
    // Set bahasa Indonesia untuk TTS
    await flutterTts.setLanguage("id-ID");
    await flutterTts.setSpeechRate(0.5); // Kecepatan bicara
  }

  Future<void> startSpeech() async {
    speechTimer = Timer.periodic(Duration(seconds: 5), (timer) async {
      if (detectedObjects.isNotEmpty) {
        // Hitung jumlah setiap jenis objek
        Map<String, int> objectCount = {};
        for (var obj in detectedObjects) {
          objectCount[obj] = (objectCount[obj] ?? 0) + 1;
        }

        // Buat teks ucapan berdasarkan jumlah objek
        String speech = 'Ada object terdeteksi ';
        objectCount.forEach((key, value) {
          if (value > 1) {
            speech += '$value $key, ';
          } else {
            speech += '$key, ';
          }
        });

        // Hilangkan koma terakhir
        speech = speech.trim().replaceAll(RegExp(r',$'), '');

        // Ucapkan teks
        await flutterTts.speak(speech);
      }
    });
  }

  @override
  void dispose() {
    speechTimer?.cancel();
    flutterTts.stop();
    super.dispose();
  }

  void stopYolo() {
    speechTimer?.cancel();
    flutterTts.stop();
    controller.dispose();
    widget.onStop();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _checkPermissions(),
      builder: (context, snapshot) {
        final allPermissionsGranted = snapshot.data ?? false;

        return !allPermissionsGranted
            ? const Center(
                child: Text("Error requesting permissions"),
              )
            : FutureBuilder<ObjectDetector>(
                future: _initObjectDetectorWithLocalModel(),
                builder: (context, snapshot) {
                  final predictor = snapshot.data;

                  return predictor == null
                      ? Container()
                      : Stack(
                          children: [
                            UltralyticsYoloCameraPreview(
                              controller: controller,
                              predictor: predictor,
                              onCameraCreated: () {
                                predictor.loadModel(useGpu: true);
                              },
                            ),
                            StreamBuilder<List<DetectedObject?>?>(
                              stream: predictor.detectionResultStream,
                              builder: (context, snapshot) {
                                final detections = snapshot.data;

                                if (detections != null) {
                                  detectedObjects = detections
                                      .map((detection) => detection!.label)
                                      .toList();
                                }
                                return detections == null
                                        ? Container()
                                        : Stack(
                                            children: detections.map((detectedObject) {
                                              final boundingBox = detectedObject!.boundingBox;

                                              return Positioned(
                                                left: boundingBox.left,
                                                top: boundingBox.top,
                                                width: boundingBox.width,
                                                height: boundingBox.height,
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    color: Colors.transparent,
                                                    border: Border.all(color: Colors.blueAccent, width: 2),
                                                    borderRadius: BorderRadius.circular(5),
                                                  ),
                                                  child: SingleChildScrollView(
                                                    child: Column(
                                                      children: [
                                                        Text(
                                                          detectedObject.label,
                                                          style: TextStyle(color: Colors.white, fontSize: 16),
                                                        ),
                                                        Text(
                                                          (detectedObject.confidence * 100)
                                                              .toInt()
                                                              .toString(),
                                                          style: TextStyle(color: Colors.white, fontSize: 16),
                                                        )
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              );
                                            }).toList(),
                                          );
                              },
                            ),
                            StreamBuilder<double?>(
                              stream: predictor.inferenceTime,
                              builder: (context, snapshot) {
                                final inferenceTime = snapshot.data;

                                return StreamBuilder<double?>(
                                  stream: predictor.fpsRate,
                                  builder: (context, snapshot) {
                                    final fpsRate = snapshot.data;

                                    return Times(
                                      inferenceTime: inferenceTime,
                                      fpsRate: fpsRate,
                                    );
                                  },
                                );
                              },
                            ),
                            // judul aplikasi
                            SafeArea(
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: Container(
                                  margin: const EdgeInsets.all(20),
                                  padding: const EdgeInsets.all(20),
                                  decoration: const BoxDecoration(
                                    borderRadius:
                                        BorderRadius.all(Radius.circular(10)),
                                    color: Colors.black54,
                                  ),
                                  child: const Text(
                                    'Object Detection',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                ),
                              ),
                            ),
                            // Tombol untuk menghentikan proses
                            SafeArea(
                              child: Align(
                                alignment: Alignment.bottomRight,
                                child: Container(
                                  margin: const EdgeInsets.all(20),
                                  child: ElevatedButton(
                                    onPressed: stopYolo,
                                    child: Icon(Icons.stop),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                },
              );
      },
    );
  }

  Future<ObjectDetector> _initObjectDetectorWithLocalModel() async {
    final modelPath = await _copy('assets/yolov8n_int8.tflite');
    final metadataPath = await _copy('assets/metadata.yaml');
    final model = LocalYoloModel(
      id: '',
      task: Task.detect,
      format: Format.tflite,
      modelPath: modelPath,
      metadataPath: metadataPath,
    );

    return ObjectDetector(model: model);
  }

  Future<String> _copy(String assetPath) async {
    final path = '${(await getApplicationSupportDirectory()).path}/$assetPath';
    await io.Directory(dirname(path)).create(recursive: true);
    final file = io.File(path);
    if (!await file.exists()) {
      final byteData = await rootBundle.load(assetPath);
      await file.writeAsBytes(byteData.buffer
          .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
    }
    return file.path;
  }

  Future<bool> _checkPermissions() async {
    List<Permission> permissions = [];

    var cameraStatus = await Permission.camera.status;
    if (!cameraStatus.isGranted) permissions.add(Permission.camera);

    if (permissions.isEmpty) {
      return true;
    } else {
      try {
        Map<Permission, PermissionStatus> statuses =
            await permissions.request();
        return statuses.values
            .every((status) => status == PermissionStatus.granted);
      } on Exception catch (_) {
        return false;
      }
    }
  }
}

class Times extends StatelessWidget {
  const Times({
    super.key,
    required this.inferenceTime,
    required this.fpsRate,
  });

  final double? inferenceTime;
  final double? fpsRate;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(10)),
              color: Colors.black54,
            ),
            child: Text(
              '${(inferenceTime ?? 0).toStringAsFixed(1)} ms  -  ${(fpsRate ?? 0).toStringAsFixed(1)} FPS',
              style: const TextStyle(color: Colors.white70),
            )),
      ),
    );
  }
}

class LTVoice  {
  
  List<DetectedObject?>? detections;
}