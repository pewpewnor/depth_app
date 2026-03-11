import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'depth_estimator.dart';
import 'dart:developer' as developer;
import 'logger.dart';

List<CameraDescription> cameras = [];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    logAndToast("Searching for cameras...", name: 'camera.init');
    cameras = await availableCameras();
    logAndToast("Found ${cameras.length} cameras", name: 'camera.init');
    
    for (var camera in cameras) {
      developer.log("Device: ${camera.name}", name: 'camera.init');
    }
  } catch (e, stackTrace) {
    developer.log(
      "Camera Error", 
      name: 'camera.init', 
      error: e, 
      stackTrace: stackTrace
    );
    cameras = [];
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Depth Estimator',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
      home: const DepthEstimatorScreen(),
    );
  }
}

class DepthEstimatorScreen extends StatefulWidget {
  const DepthEstimatorScreen({super.key});

  @override
  State<DepthEstimatorScreen> createState() => _DepthEstimatorScreenState();
}

class _DepthEstimatorScreenState extends State<DepthEstimatorScreen> {
  late CameraController _controller;
  late DepthEstimator _depthEstimator;
  double _depthMeters = 0.0;
  bool _isProcessing = false;
  String _status = "Initializing...";
  bool _cameraInitialized = false;
  
  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeDepthEstimator();
  }

  Future<void> _initializeCamera() async {
    try {
      if (cameras.isEmpty) {
        logAndToast("No cameras available", name: 'camera.init');
        setState(() => _status = "No cameras available");
        return;
      }
      
      logAndToast("Connecting to camera: ${cameras[0].name}", name: 'camera.init');
      _controller = CameraController(
        cameras[0],
        ResolutionPreset.high,
        enableAudio: false,
      );
      await _controller.initialize();
      
      if (!mounted) return;
      
      _cameraInitialized = true;
      logAndToast("Camera ready", name: 'camera.init');
      
      await _controller.startImageStream((CameraImage image) {
        if (!_isProcessing) {
          _isProcessing = true;
          _processFrame(image);
        }
      });
      
      setState(() => _status = "Ready");
    } catch (e) {
      setState(() => _status = "Camera error: $e");
    }
  }

  Future<void> _initializeDepthEstimator() async {
    try {
      _depthEstimator = DepthEstimator();
      await _depthEstimator.initialize();
      
      if (!mounted) return;
    } catch (e) {
      setState(() => _status = "Model error: $e");
    }
  }

  void _processFrame(CameraImage image) async {
    try {
      int width = image.width;
      int height = image.height;
      int bboxSize = 224;
      
      int x = (width - bboxSize) ~/ 2;
      int y = (height - bboxSize) ~/ 2;
      
      Uint8List bboxBytes = _extractBbox(image, x, y, bboxSize);
      
      double depth = await _depthEstimator.estimateDepth(bboxBytes);
      
      setState(() {
        _depthMeters = depth;
      });
    } catch (e) {
      setState(() => _status = "Processing error: $e");
    } finally {
      _isProcessing = false;
    }
  }

  Uint8List _extractBbox(CameraImage image, int x, int y, int size) {
    List<int> bytes = [];
    
    for (int yi = y; yi < y + size && yi < image.height; yi++) {
      for (int xi = x; xi < x + size && xi < image.width; xi++) {
        int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;
        int uvIndex = uvPixelStride * (xi ~/ 2) + image.planes[1].bytesPerRow * (yi ~/ 2);
        
        int pixelIndex = yi * image.planes[0].bytesPerRow + xi;
        int yValue = image.planes[0].bytes[pixelIndex];
        int uValue = image.planes[1].bytes[uvIndex];
        int vValue = image.planes[2].bytes[uvIndex];
        
        int r = (yValue + 1.402 * (vValue - 128)).clamp(0, 255).toInt();
        int g = (yValue - 0.344 * (uValue - 128) - 0.714 * (vValue - 128)).clamp(0, 255).toInt();
        int b = (yValue + 1.772 * (uValue - 128)).clamp(0, 255).toInt();
        
        bytes.addAll([r, g, b]);
      }
    }
    
    return Uint8List.fromList(bytes);
  }

  @override
  void dispose() {
    if (_cameraInitialized) {
      _controller.dispose();
    }
    _depthEstimator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Depth Estimator'),
      ),
      body: _cameraInitialized && _controller.value.isInitialized
          ? Stack(
              children: [
                CameraPreview(_controller),
                Positioned(
                  top: (MediaQuery.of(context).size.height - 224) / 2,
                  left: (MediaQuery.of(context).size.width - 224) / 2,
                  child: Container(
                    width: 224,
                    height: 224,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.red, width: 3),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 20,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Depth: ${_depthMeters.toStringAsFixed(2)} m',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _status,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Text(
                      _status,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
