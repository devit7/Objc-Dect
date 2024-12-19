import 'dart:async';
import 'dart:convert';
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
      onPressed: null,
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
      body: currentView,
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
  final controller = UltralyticsYoloCameraController(
    deferredProcessing: true,
  );
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

  // Fungsi untuk memulai proses voice
  Future<void> startSpeech() async {
    // delay 10 detik ( bisa di turunnin kok :] )
    speechTimer = Timer.periodic(Duration(seconds: 6), (timer) async {
      if (detectedObjects.isNotEmpty) {
        // Hitung jumlah setiap jenis objek
        Map<String, int> objectCount = {};
        for (var obj in detectedObjects) {
          objectCount[obj] = (objectCount[obj] ?? 0) + 1;
        }

        // terjemahan label objek ke bahasa Indonesia dari file JSON
        final String translationJson =
            await rootBundle.loadString('assets/translation.json');
        final Map<String, dynamic> labelTranslations =
            json.decode(translationJson);

        //  voice berdasarkan jumlah objek
        String speech = 'Ada objek terdeteksi ';
        objectCount.forEach((key, value) {
          // Cek apakah label ada di list translationJson
          String labelInIndonesian = labelTranslations[key] ??
              key; // pakek label asli jika tidak ada di list

          if (value > 1) {
            speech += '$value $labelInIndonesian, ';
          } else {
            speech += '$labelInIndonesian, ';
          }
        });
        // Hilangkan koma terakhir
        speech = speech.trim().replaceAll(RegExp(r',$'), '');

        // Ucapkan teks
        await flutterTts.speak(speech);

        // bersihkan detectedObjects
        detectedObjects.clear();
      }
    });
  }

// Kalkulasi jarak antara kamera dan objek
  double calculateDistance(
      double boundingBoxSize, double realObjectSize, double focalLength) {
    return (focalLength * realObjectSize) / boundingBoxSize;
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
                                // Load model saat kamera siap
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
                                        children:
                                            detections.map((detectedObject) {
                                          final boundingBox =
                                              detectedObject!.boundingBox;
                                          // untuk persiapan kalkulasi jarak
                                          // Ukuran bounding box (contoh menggunakan tinggi)
                                          final boundingBoxHeight =
                                              boundingBox.height;

                                          // Ukuran objek sebenarnya (contoh: botol tinggi 20 cm)
                                          const realObjectSize =
                                              20.0; // note: data mentah

                                          // Fokal kamera (contoh eksperimen: 700)
                                          const focalLength =
                                              700.0; // note: data mentah

                                          // Kalkulasi jarak
                                          final distance = calculateDistance(
                                              boundingBoxHeight,
                                              realObjectSize,
                                              focalLength);
                                          // bikin kotak hasil deteksi
                                          return Positioned(
                                            left: boundingBox.left,
                                            top: boundingBox.top,
                                            width: boundingBox.width,
                                            height: boundingBox.height,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: Colors.black.withOpacity(
                                                    0.3), // Tambahkan latar belakang semi transparan
                                                border: Border.all(
                                                  color: Colors.blueAccent,
                                                  width: 2,
                                                ),
                                                borderRadius: BorderRadius.circular(
                                                    8), // Radius lebih besar agar lebih halus
                                              ),
                                              padding: const EdgeInsets.all(
                                                  8), // Tambahkan padding untuk jarak dalam kotak
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment
                                                    .center, // Pusatkan teks di tengah
                                                crossAxisAlignment:
                                                    CrossAxisAlignment
                                                        .start, // Teks rata kiri
                                                children: [
                                                  Text(
                                                    // jika ada label person maka akan diubah menjadi
                                                    detectedObject.label,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 14,
                                                      fontWeight: FontWeight
                                                          .bold, // Teks tebal agar lebih menonjol
                                                    ),
                                                  ),
                                                  const SizedBox(
                                                      height:
                                                          4), // Spasi antar elemen
                                                  Text(
                                                    'Akurasi: ${(detectedObject.confidence * 100).toInt()}%',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                  const SizedBox(
                                                      height:
                                                          4), // Spasi antar elemen
                                                  Text(
                                                    '(${distance.toStringAsFixed(2)} cm)',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
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

// Inisialisasi model deteksi objek dari plugin
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

  // Salin file dari asset ke direktori aplikasi (default plugin)
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

  // chek permission app untuk kamera dll
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

// buat hitungan fps dan inference time
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
