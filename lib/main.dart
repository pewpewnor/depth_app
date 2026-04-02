import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'depth_estimator.dart';
import 'dart:developer' as developer;
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'logger.dart';

List<CameraDescription> cameras = [];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Don't search for cameras here - defer to the screen after permission is granted
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
  CameraController? _controller;
  late DepthEstimator _depthEstimator;
  double _depthMeters = 0.0;
  bool _isProcessing = false;
  String _status = "Initializing...";
  bool _cameraInitialized = false;
  bool _permissionGranted = false;
  bool _modelInitializing = false;
  String? _modelError;
  int _frameCounter = 0;
  DateTime? _lastInferenceTime;
  
  @override
  void initState() {
    super.initState();
    _initializeApp();
    _initializeDepthEstimator();
  }

  Future<void> _initializeApp() async {
    try {
      // Request camera permission first
      await _requestCameraPermission();
      
      if (!_permissionGranted) {
        if (mounted) {
          setState(() => _status = "Camera permission denied");
        }
        logAndToast("Camera permission denied. Please enable it in settings.", name: 'permission');
        return;
      }

      // Now search for cameras after permission is granted
      await _searchAndInitializeCamera();
    } catch (e, stackTrace) {
      developer.log(
        "Initialization Error", 
        name: 'init', 
        error: e, 
        stackTrace: stackTrace
      );
      if (mounted) {
        setState(() => _status = "Initialization failed: $e");
      }
    }
  }

  Future<void> _requestCameraPermission() async {
    try {
      // Desktop platforms may not need camera permission
      if (_isDesktopPlatform()) {
        developer.log("Desktop platform - skipping permission request", name: 'permission');
        _permissionGranted = true;
        return;
      }
      
      final status = await Permission.camera.request();
      
      if (status.isGranted) {
        logAndToast("Camera permission granted", name: 'permission');
        _permissionGranted = true;
      } else if (status.isPermanentlyDenied) {
        logAndToast("Camera permission permanently denied. Opening app settings.", name: 'permission');
        openAppSettings();
        _permissionGranted = false;
      } else {
        logAndToast("Camera permission denied", name: 'permission');
        _permissionGranted = false;
      }
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      developer.log("Permission request error", name: 'permission', error: e);
      // On desktop, still allow to proceed
      if (_isDesktopPlatform()) {
        _permissionGranted = true;
      } else {
        _permissionGranted = false;
      }
    }
  }

  Future<void> _searchAndInitializeCamera() async {
    try {
      developer.log("App search dir: Platform=$defaultTargetPlatform", name: 'camera.init');
      logAndToast("Searching for cameras on ${_getPlatformName()}...", name: 'camera.init');
      
      // Attempt to get available cameras
      try {
        final availableCameras_ = await availableCameras().timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException('Camera detection timed out after 5 seconds'),
        );
        cameras = availableCameras_;
        
        developer.log("Found ${cameras.length} camera(s)", name: 'camera.init');
        logAndToast("Found ${cameras.length} cameras", name: 'camera.init');
        
        for (var camera in cameras) {
          developer.log("Device: ${camera.name}, Lens: ${camera.lensDirection}", name: 'camera.init');
        }
        
        if (cameras.isEmpty) {
          if (mounted) {
            setState(() => _status = "No cameras available on this device");
          }
          logAndToast("No cameras available", name: 'camera.init');
          return;
        }
        
        if (!mounted) return;
        await _initializeCamera();
      } on MissingPluginException catch (e) {
        // Plugin not found - likely on desktop or plugin not properly installed
        developer.log(
          "MissingPluginException: Camera plugin not found", 
          name: 'camera.init', 
          error: e
        );
        
        // For desktop platforms, try fallback
        if (_isDesktopPlatform()) {
          _handleDesktopCameraNotSupported();
          return;
        }
        
        // For mobile, this is an installation issue
        _handleCameraPluginNotFound();
      } on TimeoutException catch (e) {
        developer.log("Camera detection timeout", name: 'camera.init', error: e);
        _handleCameraTimeout();
      }
    } catch (e, stackTrace) {
      developer.log(
        "Camera Search Error", 
        name: 'camera.init', 
        error: e, 
        stackTrace: stackTrace
      );
      if (mounted) {
        setState(() => _status = "Camera search error: $e");
      }
      logAndToast("Error searching for cameras: $e", name: 'camera.init');
    }
  }

  bool _isDesktopPlatform() {
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  String _getPlatformName() {
    if (defaultTargetPlatform == TargetPlatform.android) return "Android";
    if (defaultTargetPlatform == TargetPlatform.iOS) return "iOS";
    if (defaultTargetPlatform == TargetPlatform.windows) return "Windows";
    if (defaultTargetPlatform == TargetPlatform.linux) return "Linux";
    if (defaultTargetPlatform == TargetPlatform.macOS) return "macOS";
    return "Unknown";
  }

  void _handleDesktopCameraNotSupported() {
    developer.log("Desktop platform detected - camera not supported yet", name: 'camera.init');
    if (mounted) {
      setState(() {
        _status = "Camera not available on ${_getPlatformName()}\n"
            "Desktop support coming soon!";
        _cameraInitialized = false;
      });
    }
    logAndToast("Camera not yet supported on ${_getPlatformName()}", name: 'camera.init');
  }

  void _handleCameraPluginNotFound() {
    developer.log("Camera plugin not properly installed for mobile", name: 'camera.init');
    if (mounted) {
      setState(() {
        _status = "Camera plugin error\n"
            "Please run: flutter clean && flutter pub get && flutter run";
        _cameraInitialized = false;
      });
    }
    logAndToast("Camera plugin not found - rebuild needed", name: 'camera.init');
  }

  void _handleCameraTimeout() {
    developer.log("Camera detection timed out", name: 'camera.init');
    if (mounted) {
      setState(() {
        _status = "Camera detection timed out\nRebuild the app to fix";
        _cameraInitialized = false;
      });
    }
    logAndToast("Camera detection timeout", name: 'camera.init');
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
        ResolutionPreset.medium,
        enableAudio: false,
      );
      
      if (_controller == null) {
        if (mounted) {
          setState(() => _status = "Failed to create camera controller");
        }
        return;
      }
      
      await _controller!.initialize();
      
      if (!mounted) return;
      
      _cameraInitialized = true;
      logAndToast("Camera ready", name: 'camera.init');
      setState(() => _status = "Ready");
      
      try {
        await _controller!.startImageStream((CameraImage image) {
          if (!_isProcessing) {
            _isProcessing = true;
            _processFrame(image);
          }
        });
      } catch (e) {
        developer.log("Image stream error", name: 'camera.stream', error: e);
        logAndToast("Error starting image stream: $e", name: 'camera.stream');
      }
    } catch (e, stackTrace) {
      developer.log(
        "Camera Initialization Error", 
        name: 'camera.init', 
        error: e, 
        stackTrace: stackTrace
      );
      if (mounted) {
        setState(() => _status = "Camera error: $e");
      }
      logAndToast("Camera initialization failed: $e", name: 'camera.init');
    }
  }

  Future<void> _initializeDepthEstimator() async {
    try {
      if (mounted) {
        setState(() {
          _modelInitializing = true;
          _modelError = null;
        });
      }
      
      logAndToast("Initializing DepthEstimator...", name: "depth_estimator");
      _depthEstimator = DepthEstimator();
      
      try {
        logAndToast("Starting model initialization...", name: "depth_estimator");
        await _depthEstimator.initialize();
        logAndToast("✓ DepthEstimator initialized successfully", name: "depth_estimator");
        
        if (mounted) {
          setState(() {
            _modelInitializing = false;
            _modelError = null;
          });
        }
      } catch (e, stackTrace) {
        developer.log(
          "DepthEstimator initialization error", 
          name: 'depth_estimator', 
          error: e, 
          stackTrace: stackTrace
        );
        
        final errorMsg = e.toString();
        logAndToast("✗ DepthEstimator error: $errorMsg", name: "depth_estimator");
        
        if (mounted) {
          setState(() {
            _modelInitializing = false;
            _modelError = errorMsg;
          });
        }
        
        // Log detailed error for debugging
        debugPrint('DepthEstimator init failed: $e');
        debugPrintStack(stackTrace: stackTrace);
      }
      
      if (!mounted) return;
    } catch (e, stackTrace) {
      developer.log(
        "Model initialization error", 
        name: 'model', 
        error: e, 
        stackTrace: stackTrace
      );
      
      if (mounted) {
        setState(() {
          _modelInitializing = false;
          _modelError = e.toString();
        });
      }
      logAndToast("Model error: $e", name: "model");
    }
  }
  
  Future<void> _retryModelInitialization() async {
    logAndToast("Retrying model initialization...", name: "depth_estimator");
    await _initializeDepthEstimator();
  }

  void _processFrame(CameraImage image) async {
    try {
      // Increment frame counter
      _frameCounter++;
      
      // Only process every 10th frame for depth inference
      if (_frameCounter % 10 != 0) {
        _isProcessing = false;
        return;
      }

      // Extract full frame as RGB
      Uint8List fullFrameRgb = _extractFullFrame(image);
      
      double depth = await _depthEstimator.estimateDepth(fullFrameRgb, image.width, image.height);
      
      setState(() {
        _depthMeters = depth;
        _lastInferenceTime = DateTime.now();
      });
    } catch (e) {
      // Display depth model error instead of falling back
      setState(() {
        _modelError = e.toString();
        _status = "Depth model error: $e";
      });
    } finally {
      _isProcessing = false;
    }
  }

  Uint8List _extractFullFrame(CameraImage image) {
    List<int> bytes = [];
    
    for (int yi = 0; yi < image.height; yi++) {
      for (int xi = 0; xi < image.width; xi++) {
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

  void _showCalibrationDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return _CalibrationDialog(
          depthEstimator: _depthEstimator,
          controller: _controller,
          currentDepthReading: _depthMeters,
          onCalibrationSaved: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Calibration saved successfully!')),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    if (_cameraInitialized && _controller != null) {
      try {
        _controller!.dispose();
      } catch (e) {
        developer.log("Error disposing camera", name: 'camera.dispose', error: e);
      }
    }
    _depthEstimator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Depth Estimator'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Calibrate',
            onPressed: _showCalibrationDialog,
          ),
        ],
      ),
      body: _cameraInitialized && _controller != null && _controller!.value.isInitialized
          ? Stack(
              children: [
                CameraPreview(_controller!),
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    width: 120,
                    height: 120,
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
                        if (_lastInferenceTime != null)
                          Text(
                            'Last Update: ${_lastInferenceTime!.hour.toString().padLeft(2, '0')}:${_lastInferenceTime!.minute.toString().padLeft(2, '0')}:${_lastInferenceTime!.second.toString().padLeft(2, '0')}',
                            style: const TextStyle(
                              color: Colors.yellow,
                              fontSize: 12,
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
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_modelInitializing)
                      const CircularProgressIndicator()
                    else if (_modelError != null)
                      const Icon(Icons.error, color: Colors.red, size: 64)
                    else
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
                    if (_modelError != null)
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            border: Border.all(color: Colors.red, width: 2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Model Loading Error:',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _modelError!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Solutions:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                '1. Retry: The model might load on next attempt\n'
                                '2. Rebuild: Run "flutter clean && flutter build apk" to ensure model is bundled\n'
                                '3. Continue: App can work with basic depth estimation',
                                style: TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (!_permissionGranted)
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: ElevatedButton(
                          onPressed: () async {
                            await _requestCameraPermission();
                            if (_permissionGranted) {
                              if (mounted) {
                                await _searchAndInitializeCamera();
                              }
                            }
                          },
                          child: const Text('Grant Camera Permission'),
                        ),
                      ),
                    if (_modelError != null && !_modelInitializing)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: ElevatedButton.icon(
                          onPressed: _retryModelInitialization,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry Model Load'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _CalibrationDialog extends StatefulWidget {
  final DepthEstimator depthEstimator;
  final CameraController? controller;
  final double currentDepthReading;
  final VoidCallback onCalibrationSaved;

  const _CalibrationDialog({
    required this.depthEstimator,
    required this.controller,
    required this.currentDepthReading,
    required this.onCalibrationSaved,
  });

  @override
  State<_CalibrationDialog> createState() => _CalibrationDialogState();
}

class _CalibrationDialogState extends State<_CalibrationDialog> {
  final TextEditingController _distanceController = TextEditingController();
  double? _capturedDepth;
  bool _isCapturing = false;

  @override
  void dispose() {
    _distanceController.dispose();
    super.dispose();
  }

  Future<void> _captureSnapshot() async {
    try {
      setState(() => _isCapturing = true);
      
      // Capture current depth reading at calibration time
      _capturedDepth = widget.currentDepthReading;
      
      // Show confirmation dialog with image
      if (widget.controller != null) {
        try {
          final XFile picture = await widget.controller!.takePicture();
          final bytes = await picture.readAsBytes();
          
          if (!mounted) return;
          
          await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Snapshot Captured'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.memory(bytes, height: 200),
                  const SizedBox(height: 16),
                  Text(
                    'Depth Reading: ${_capturedDepth?.toStringAsFixed(2)} m',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('Now enter the actual distance to calibrate.')
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        } catch (e) {
          debugPrint('Error taking picture: $e');
        }
      }
      
      setState(() => _isCapturing = false);
    } catch (e) {
      setState(() => _isCapturing = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error capturing snapshot: $e')),
      );
    }
  }

  Future<void> _saveCalibration() async {
    if (_distanceController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the real distance')),
      );
      return;
    }

    if (_capturedDepth == null || _capturedDepth == 0.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please capture a snapshot first')),
      );
      return;
    }

    try {
      final realDistance = double.parse(_distanceController.text);
      
      // Use the captured depth reading as the raw model output for calibration
      await widget.depthEstimator.saveCalibration(_capturedDepth!, realDistance);
      
      if (!mounted) return;
      
      Navigator.pop(context);
      widget.onCalibrationSaved();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Calibrate Depth'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'To calibrate the depth sensor, place a known-distance object in the center of the camera view (in the red box) and then:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isCapturing ? null : _captureSnapshot,
              icon: const Icon(Icons.camera),
              label: const Text('Capture Current View'),
            ),
            if (_capturedDepth != null) ...[
              const SizedBox(height: 16),
              Text(
                'Model Output: ${_capturedDepth?.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _distanceController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Real Distance (meters)',
                hintText: 'e.g., 2.5',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.straighten),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'The current depth reading will be calibrated to match the distance you enter.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saveCalibration,
          child: const Text('Save Calibration'),
        ),
      ],
    );
  }
}
