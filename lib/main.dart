import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/services.dart';
import 'depth_estimator.dart';

late List<CameraDescription> cameras;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
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
  
  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeDepthEstimator();
  }

  Future<void> _initializeCamera() async {
    try {
      _controller = CameraController(
        cameras[0],
        ResolutionPreset.high,
        enableAudio: false,
      );
      await _controller.initialize();
      
      if (!mounted) return;
      
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
        int y_value = image.planes[0].bytes[pixelIndex];
        int u_value = image.planes[1].bytes[uvIndex];
        int v_value = image.planes[2].bytes[uvIndex];
        
        int r = (y_value + 1.402 * (v_value - 128)).clamp(0, 255).toInt();
        int g = (y_value - 0.344 * (u_value - 128) - 0.714 * (v_value - 128)).clamp(0, 255).toInt();
        int b = (y_value + 1.772 * (u_value - 128)).clamp(0, 255).toInt();
        
        bytes.addAll([r, g, b]);
      }
    }
    
    return Uint8List.fromList(bytes);
  }

  @override
  void dispose() {
    _controller.dispose();
    _depthEstimator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Depth Estimator'),
      ),
      body: _controller.value.isInitialized
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
                  const SizedBox(height: 16),
                  Text(_status),
                ],
              ),
            ),
    );
  }
}

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          //
          // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
          // action in the IDE, or press "p" in the console), to see the
          // wireframe for each widget.
          mainAxisAlignment: .center,
          children: [
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
