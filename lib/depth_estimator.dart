import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'logger.dart';

class DepthEstimator {
  static const platform = MethodChannel('com.depth.app/depth');
  
  bool _isInitialized = false;
  bool _useNative = false;
  OrtSession? _ortSession;
  late double _calibrationValue;
  late double _calibrationDistance;

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
      
      // Load calibration from SharedPreferences
      await loadCalibration();
      
      // Try to get model path
      String? modelPath;
      try {
        modelPath = await _getModelPath();
        logAndToast("Model path obtained: $modelPath", name: "depth_estimator");
      } catch (e) {
        logAndToast("Failed to get model path: $e", name: "depth_estimator");
        debugPrint('DepthEstimator: Failed to get model path: $e');
        // Don't silently continue - throw error
        throw Exception("Cannot load depth model: $e");
      }

      // At this point modelPath is guaranteed to be non-null
      if (modelPath.isNotEmpty) {
        // Initialize ONNX Runtime locally for offline inference
        logAndToast("Attempting ONNX initialization with model: $modelPath", name: "depth_estimator");
        _initializeONNXRuntime(modelPath);
        
        // Check if ONNX initialization actually succeeded
        if (_ortSession == null) {
          throw Exception("Failed to initialize ONNX runtime with model");
        }
        
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
      } else {
        throw Exception("Model path is empty");
      }
      
      _isInitialized = true;
      logAndToast("DepthEstimator fully initialized", name: "depth_estimator");
    } catch (e, stackTrace) {
      debugPrint('DepthEstimator: Initialization error: $e');
      debugPrintStack(stackTrace: stackTrace);
      logAndToast('DepthEstimator: Failed to initialize: $e', name: "depth_estimator");
      _isInitialized = false;
      // Don't silently fail - rethrow the error
      rethrow;
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

  Future<double> estimateDepth(Uint8List frameRgb, int frameWidth, int frameHeight) async {
    if (!_isInitialized) {
      return 0.0;
    }

    if (_useNative) {
      return _estimateDepthNative(frameRgb, frameWidth, frameHeight);
    } else {
      return _estimateDepthOffline(frameRgb, frameWidth, frameHeight);
    }
  }

  Future<double> _estimateDepthNative(Uint8List bboxBytes, int frameWidth, int frameHeight) async {
    try {
      final double rawDepth = await platform.invokeMethod<double>(
        'estimateDepth',
        {
          'imageBytes': bboxBytes,
          'frameWidth': frameWidth,
          'frameHeight': frameHeight,
        },
      ) ?? 0.0;
      
      return _calibrateDepth(rawDepth);
    } catch (e) {
      debugPrint('DepthEstimator: Native depth estimation failed: $e');
      // Throw error instead of silently returning 0.0
      throw Exception('Depth model native inference failed: $e');
    }
  }

  double _estimateDepthOffline(Uint8List frameRgb, int frameWidth, int frameHeight) {
    if (frameRgb.isEmpty) return 0.0;
    
    // Only use ONNX model - no fallback algorithms
    if (_ortSession == null) {
      throw Exception('Depth model not initialized. Cannot perform depth estimation.');
    }

    try {
      // frameRgb is RGB byte array from entire camera frame.
      // Resize to 518x518 which is what the model expects.

      int targetSize = 518;
      Float32List float32list = Float32List(1 * 3 * targetSize * targetSize);

      // Nearest Neighbor scaling to 518x518 for the full frame
      for (int c = 0; c < 3; c++) {
        for (int y = 0; y < targetSize; y++) {
          for (int x = 0; x < targetSize; x++) {
            int srcX = (x * frameWidth ~/ targetSize).clamp(0, frameWidth - 1);
            int srcY = (y * frameHeight ~/ targetSize).clamp(0, frameHeight - 1);
            int srcIdx = (srcY * frameWidth + srcX) * 3 + c;

            int dstIdx = c * (targetSize * targetSize) + y * targetSize + x;
            float32list[dstIdx] = frameRgb[srcIdx] / 255.0; // normalize
          }
        }
      }

      final shape = [1, 3, targetSize, targetSize];
      final tensor = OrtValueTensor.createTensorWithDataList(float32list, shape);
      final runOptions = OrtRunOptions();

      final inputs = {'pixel_values': tensor};
      final outputs = _ortSession!.run(runOptions, inputs);

      final outputTensor = outputs[0]?.value as List<dynamic>;
      
      // Find min and max from entire depth map for normalization
      double minDepth = double.infinity;
      double maxDepth = double.negativeInfinity;
      
      if (outputTensor.isNotEmpty) {
        // Output is [1, 518, 518]
        List<dynamic> firstBatch = outputTensor[0] as List<dynamic>;
        for (var row in firstBatch) {
          for (var val in row) {
            double v = val.toDouble();
            if (v < minDepth) minDepth = v;
            if (v > maxDepth) maxDepth = v;
          }
        }
      }

      // Extract center region depth (corresponding to the red square bbox)
      // The red square corresponds to the center 120x120 area in the original frame
      // Which maps to a center region in the 518x518 depth map
      int bboxSize120 = 120;
      int centerRegionSize = (bboxSize120 * targetSize) ~/ frameWidth;
      int centerStart = (targetSize - centerRegionSize) ~/ 2;
      int centerEnd = centerStart + centerRegionSize;
      
      double centerDepthSum = 0.0;
      int centerPixelCount = 0;
      
      if (outputTensor.isNotEmpty) {
        List<dynamic> firstBatch = outputTensor[0] as List<dynamic>;
        for (int y = centerStart; y < centerEnd && y < firstBatch.length; y++) {
          var row = firstBatch[y] as List<dynamic>;
          for (int x = centerStart; x < centerEnd && x < row.length; x++) {
            centerDepthSum += row[x].toDouble();
            centerPixelCount++;
          }
        }
      }

      // Calculate average depth in center region
      double centerAverageDepth = centerPixelCount > 0 ? (centerDepthSum / centerPixelCount) : 0.0;
      
      // Normalize to 0-255 range for consistency
      double normalizedDepth = 0.0;
      double depthRange = maxDepth - minDepth;
      if (depthRange > 0) {
        // Normalize to 0-1, then scale to 0-255
        normalizedDepth = ((centerAverageDepth - minDepth) / depthRange) * 255.0;
      } else {
        // If all values are the same, use the value as-is
        normalizedDepth = centerAverageDepth;
      }

      tensor.release();
      runOptions.release();
      for (var out in outputs) {
        out?.release();
      }

      return _calibrateDepth(normalizedDepth);
    } catch (e) {
      debugPrint('DepthEstimator: ONNX inference failed: $e');
      // Re-throw the error instead of falling back
      throw Exception('Depth model inference failed: $e');
    }
  }

  double _calibrateDepth(double rawValue) {
    if (rawValue == 0) return 0.0;
    return (rawValue / _calibrationValue) * _calibrationDistance;
  }

  Future<void> loadCalibration() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Check if user has saved calibration values in SharedPreferences
      final savedValue = prefs.getDouble('calibration_value');
      final savedDistance = prefs.getDouble('calibration_distance');
      
      if (savedValue != null && savedDistance != null) {
        // Use saved calibration
        _calibrationValue = savedValue;
        _calibrationDistance = savedDistance;
        logAndToast("Loaded calibration from saved data: value=$_calibrationValue, distance=$_calibrationDistance", name: "calibration");
        return;
      }
      
      // If no saved calibration, try to load from JSON asset (bundled calibration)
      try {
        final jsonString = await rootBundle.loadString('assets/models/calibration.json');
        final jsonData = json.decode(jsonString) as Map<String, dynamic>;
        
        final calibrationData = jsonData['calibration'] as Map<String, dynamic>?;
        if (calibrationData != null) {
          _calibrationValue = (calibrationData['default_value'] as num?)?.toDouble() ?? 147.0;
          _calibrationDistance = (calibrationData['default_distance_meters'] as num?)?.toDouble() ?? 6.0;
          logAndToast("Loaded calibration from JSON: value=$_calibrationValue, distance=$_calibrationDistance", name: "calibration");
          return;
        }
      } catch (e) {
        logAndToast("Note: Calibration JSON not found in assets, using defaults", name: "calibration");
      }
      
      // Fallback to default values
      _calibrationValue = 147.0;
      _calibrationDistance = 6.0;
      logAndToast("Using default calibration values: value=$_calibrationValue, distance=$_calibrationDistance", name: "calibration");
    } catch (e) {
      // Set defaults if all loading fails
      _calibrationValue = 147.0;
      _calibrationDistance = 6.0;
      logAndToast("Failed to load calibration, using defaults: $e", name: "calibration");
      debugPrint('DepthEstimator: Failed to load calibration: $e');
    }
  }

  Future<void> saveCalibration(double modelOutput, double realDistance) async {
    try {
      _calibrationValue = modelOutput;
      _calibrationDistance = realDistance;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('calibration_value', modelOutput);
      await prefs.setDouble('calibration_distance', realDistance);
      logAndToast("Saved calibration: value=$modelOutput, distance=$realDistance", name: "calibration");
    } catch (e) {
      logAndToast("Failed to save calibration: $e", name: "calibration");
      debugPrint('DepthEstimator: Failed to save calibration: $e');
    }
  }

  Future<String> getCalibrationInfo() async {
    return "Calibration Value: ${_calibrationValue.toStringAsFixed(2)}\nCalibration Distance: ${_calibrationDistance.toStringAsFixed(2)}m";
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
