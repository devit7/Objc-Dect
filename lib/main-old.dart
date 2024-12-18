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

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: currentIndex != 1
            ? AppBar(
                title: const Text('Object Detection App'),
                backgroundColor: Colors.blue,
              )
            : null,
        body: IndexedStack(
          index: currentIndex,
          children: [
            const Center(child: Text('Home Page')), // Halaman Home
            _buildDetectionPage(), // Halaman Detection
            const Center(child: Text('Profile Page')), // Halaman Profile
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: (index) {
            setState(() {
              currentIndex = index;
            });
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.camera),
              label: 'Detection',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetectionPage() {
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
                            StreamBuilder(
                              stream: predictor.detectionResultStream,
                              builder: (context, snapshot) {
                                final detections = snapshot.data;

                                if (detections != null) {
                                  detectedObjects = detections.map((detection) => detection!.label).toList();
                                }

                                return Container();
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
                          ],
                        );
                },
              );
      },
    );
  }
    void startSpeech() {
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
