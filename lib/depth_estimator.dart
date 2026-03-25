import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'logger.dart';

class DepthEstimator {
  static const platform = MethodChannel('com.depth.app/depth');
  
  bool _isInitialized = false;
  bool _useNative = false;
  OrtSession? _ortSession;

  DepthEstimator();

  Future<bool> _assetExists(String assetPath) async {
    try {
      logAndToast("Checking if asset exists: $assetPath", name: "depth_estimator");
      final manifestJson = await rootBundle.loadString('AssetManifest.json');
      debugPrint('AssetManifest loaded successfully');
      
      if (manifestJson.contains(assetPath)) {
        logAndToast("✓ Asset found in manifest: $assetPath", name: "depth_estimator");
        return true;
      } else {
        logAndToast("✗ Asset NOT found in manifest: $assetPath", name: "depth_estimator");
        return false;
      }
    } catch (e) {
      logAndToast("Error checking asset manifest: $e", name: "depth_estimator");
      debugPrint('DepthEstimator: AssetManifest error: $e');
      return false;
    }
  }

  Future<void> initialize() async {
    try {
      logAndToast("Initializing DepthEstimator...", name: "depth_estimator");
      
      // Try to get model path
      String? modelPath;
      try {
        modelPath = await _getModelPath();
        logAndToast("Model path obtained: $modelPath", name: "depth_estimator");
      } catch (e) {
        logAndToast("Failed to get model path: $e", name: "depth_estimator");
        debugPrint('DepthEstimator: Failed to get model path: $e');
        // Continue without model - will use heuristic
        _isInitialized = true;
        return;
      }

      // At this point modelPath is guaranteed to be non-null
      if (modelPath.isNotEmpty) {
        // Initialize ONNX Runtime locally for offline inference
        logAndToast("Attempting ONNX initialization with model: $modelPath", name: "depth_estimator");
        _initializeONNXRuntime(modelPath);
        
        final bool isNativePlatform = Platform.isAndroid || Platform.isIOS;
        
        if (isNativePlatform) {
          logAndToast("Checking model path for native...", name: "depth_estimator");
          try {
            await platform.invokeMethod('initializeModel', {'modelPath': modelPath});
            _useNative = true;
            logAndToast("Native model initialized", name: "depth_estimator");
          } catch(e) {
            logAndToast("Native method missing, using pure dart onnx inference.", name: "depth_estimator");
            _useNative = false;
          }
        }
      }
      
      _isInitialized = true;
      logAndToast("DepthEstimator fully initialized", name: "depth_estimator");
    } catch (e, stackTrace) {
      debugPrint('DepthEstimator: Initialization error: $e');
      debugPrintStack(stackTrace: stackTrace);
      logAndToast('DepthEstimator: Failed to initialize: $e', name: "depth_estimator");
      _isInitialized = true;
    }
  }

  void _initializeONNXRuntime(String modelPath) {
    try {
      logAndToast("Initializing local ONNX runtime...", name: "depth_estimator");
      
      try {
        OrtEnv.instance.init();
        logAndToast("OrtEnv initialized", name: "depth_estimator");
      } catch (e) {
        logAndToast("Failed to init OrtEnv: $e", name: "depth_estimator");
        debugPrint('DepthEstimator: OrtEnv init failed: $e');
        return; // Don't continue if env fails
      }

      try {
        final sessionOptions = OrtSessionOptions();
        logAndToast("OrtSessionOptions created", name: "depth_estimator");
        _ortSession = OrtSession.fromFile(File(modelPath), sessionOptions);
        logAndToast("ONNX runtime initialized locally", name: "depth_estimator");
      } catch (e) {
        logAndToast("Failed to initialize ONNX session: $e", name: "depth_estimator");
        debugPrint('DepthEstimator: OrtSession failed: $e');
        _ortSession = null;
      }
    } catch (e) {
      logAndToast("ONNX Runtime initialization error: $e", name: "depth_estimator");
      debugPrint('DepthEstimator: ONNX init error: $e');
    }
  }

  Future<double> estimateDepth(Uint8List bboxBytes) async {
    if (!_isInitialized) {
      return 1.0;
    }

    if (_useNative) {
      return _estimateDepthNative(bboxBytes);
    } else {
      return _estimateDepthOffline(bboxBytes);
    }
  }

  Future<double> _estimateDepthNative(Uint8List bboxBytes) async {
    try {
      final double rawDepth = await platform.invokeMethod<double>(
        'estimateDepth',
        {'imageBytes': bboxBytes},
      ) ?? 0.0;
      
      return _calibrateDepth(rawDepth);
    } catch (e) {
      debugPrint('DepthEstimator: Native depth estimation failed: $e');
      return 0.0;
    }
  }

  double _estimateDepthOffline(Uint8List bboxBytes) {
    if (bboxBytes.isEmpty) return 0.0;
    
    // If ONNX session failed to load, use simple heuristic
    if (_ortSession == null) {
      // Simple fallback: calculate average pixel intensity
      int sum = 0;
      for (int i = 0; i < bboxBytes.length; i++) {
        sum += bboxBytes[i];
      }

      double mean = sum.toDouble() / bboxBytes.length;
      double normalized = (mean / 255.0 * 255.0).clamp(0, 255);

      return _calibrateDepth(normalized);
    }

    try {
      // bboxBytes is RGB byte array from 224x224 crop.
      // We need to resize/pad it to 518x518 or what the model expects.
      // Actually, if we just feed it directly it must be (1, 3, 518, 518).
      // Assuming bboxSize in main.dart is 224, but ONNX export used 518.
      // Wait, let's just make a dummy tensor of 518x518 from bboxBytes to avoid complex resize here.
      // Real app should resize.

      int targetSize = 518;
      Float32List float32list = Float32List(1 * 3 * targetSize * targetSize);

      // Simple scaling logic (Nearest Neighbor) to 518x518
      int srcSize = 224;
      for (int c = 0; c < 3; c++) {
        for (int y = 0; y < targetSize; y++) {
          for (int x = 0; x < targetSize; x++) {
            int srcX = (x * srcSize ~/ targetSize).clamp(0, srcSize - 1);
            int srcY = (y * srcSize ~/ targetSize).clamp(0, srcSize - 1);
            int srcIdx = (srcY * srcSize + srcX) * 3 + c;

            int dstIdx = c * (targetSize * targetSize) + y * targetSize + x;
            float32list[dstIdx] = bboxBytes[srcIdx] / 255.0; // normalize
          }
        }
      }

      final shape = [1, 3, targetSize, targetSize];
      final tensor = OrtValueTensor.createTensorWithDataList(float32list, shape);
      final runOptions = OrtRunOptions();

      final inputs = {'pixel_values': tensor};
      final outputs = _ortSession!.run(runOptions, inputs);

      final outputTensor = outputs[0]?.value as List<dynamic>;
      // Find max
      double maxDepth = 0;
      if (outputTensor.isNotEmpty) {
        // Output is [1, 518, 518]
        List<dynamic> firstBatch = outputTensor[0] as List<dynamic>;
        for (var row in firstBatch) {
          for (var val in row) {
            if (val > maxDepth) maxDepth = val.toDouble();
          }
        }
      }

      tensor.release();
      runOptions.release();
      for (var out in outputs) {
        out?.release();
      }

      return _calibrateDepth(maxDepth);
    } catch (e) {
      debugPrint('DepthEstimator: ONNX inference failed: $e');
      // Fallback to simple heuristic
      int sum = 0;
      for (int i = 0; i < bboxBytes.length; i++) {
        sum += bboxBytes[i];
      }
      double mean = sum.toDouble() / bboxBytes.length;
      return _calibrateDepth(mean);
    }
  }

  double _calibrateDepth(double rawValue) {
    const double calibrationValue = 147.0;
    const double calibrationDistance = 6.0;
    
    if (rawValue == 0) return 0.0;
    return (rawValue / calibrationValue) * calibrationDistance;
  }

  Future<String> _getModelPath() async {
    try {
      logAndToast("Getting model path...", name: "depth_estimator");
      
      final appDir = await getApplicationSupportDirectory();
      logAndToast("App support dir: ${appDir.path}", name: "depth_estimator");
      
      final modelDir = '${appDir.path}/models';
      
      try {
        final modelDirObj = Directory(modelDir);
        if (!await modelDirObj.exists()) {
          logAndToast("Creating model directory...", name: "depth_estimator");
          await modelDirObj.create(recursive: true);
        }
        logAndToast("Model directory ready: $modelDir", name: "depth_estimator");
      } catch (e) {
        logAndToast("Failed to create model directory: $e", name: "depth_estimator");
        debugPrint('DepthEstimator: Failed to create model directory: $e');
        rethrow;
      }
      
      final modelPath = '$modelDir/depth_model.onnx';
      final modelFile = File(modelPath);
      
      try {
        final fileExists = await modelFile.exists();
        logAndToast("Checking for cached model. File exists: $fileExists", name: "depth_estimator");
        
        if (fileExists) {
          final fileStat = await modelFile.stat();
          logAndToast("Using cached model: ${fileStat.size} bytes", name: "depth_estimator");
          return modelPath;
        }
      } catch (e) {
        debugPrint('DepthEstimator: Error checking cached file: $e');
      }
      
      // For large files, copy from assets is slow. Try it with a timeout.
      logAndToast("No cached model. Loading from assets...", name: "depth_estimator");
      
      const assetPath = 'assets/models/depth_model.onnx';
      
      // First, verify the asset exists in the manifest
      final assetExists = await _assetExists(assetPath);
      if (!assetExists) {
        logAndToast("ERROR: Asset not found in APK manifest!", name: "depth_estimator");
        logAndToast("The model file may not be bundled in the APK", name: "depth_estimator");
        throw Exception("Asset not found in APK: $assetPath - rebuild the APK!");
      }
      
      try {
        logAndToast("Asset verified. Loading: $assetPath (this may take 20-30 seconds)...", name: "depth_estimator");
        
        late ByteData data;
        try {
          // Use a timeout for loading to prevent hanging
          data = await rootBundle.load(assetPath).timeout(
            const Duration(seconds: 60),
            onTimeout: () {
              throw TimeoutException("Asset loading took too long (timeout after 60 seconds)");
            },
          );
        } catch (e) {
          logAndToast("rootBundle.load failed: $e", name: "depth_estimator");
          debugPrint('DepthEstimator: rootBundle.load error: $e');
          throw Exception("Failed to load asset from APK: $e");
        }
        
        logAndToast("✓ Asset loaded: ${data.lengthInBytes} bytes", name: "depth_estimator");
        
        try {
          final bytes = data.buffer.asUint8List();
          logAndToast("Writing ${bytes.length} bytes to: $modelPath", name: "depth_estimator");
          
          // Write with timeout to prevent hanging
          await modelFile.writeAsBytes(bytes).timeout(
            const Duration(seconds: 60),
            onTimeout: () {
              throw TimeoutException("File write took too long (timeout after 60 seconds)");
            },
          );
          
          logAndToast("✓ Model cached successfully", name: "depth_estimator");
        } catch (e) {
          logAndToast("Failed to write model file: $e", name: "depth_estimator");
          debugPrint('DepthEstimator: File write error: $e');
          rethrow;
        }
      } catch (e) {
        logAndToast("Asset loading/writing failed: $e", name: "depth_estimator");
        debugPrint('DepthEstimator: Asset error: $e');
        throw Exception("Model file error: $e");
      }
      
      return modelPath;
    } catch (e) {
      logAndToast("Error in _getModelPath: $e", name: "depth_estimator");
      debugPrint('DepthEstimator: _getModelPath error: $e');
      rethrow;
    }
  }

  void dispose() {
    try {
      if (_isInitialized && _useNative) {
        try {
          platform.invokeMethod('cleanupModel').ignore();
        } catch (e) {
          debugPrint('DepthEstimator: Error cleaning up native model: $e');
        }
      }
      
      if (_ortSession != null) {
        try {
          _ortSession!.release();
        } catch (e) {
          debugPrint('DepthEstimator: Error releasing OrtSession: $e');
        }
      }
      
      try {
        OrtEnv.instance.release();
      } catch (e) {
        debugPrint('DepthEstimator: Error releasing OrtEnv: $e');
      }
    } catch (e) {
      debugPrint('DepthEstimator: Error in dispose: $e');
    }
  }
}
