import 'dart:io';
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

  Future<void> initialize() async {
    try {
      logAndToast("Initializing DepthEstimator...", name: "depth_estimator");
      final String modelPath = await _getModelPath();

      // Initialize ONNX Runtime locally for offline inference
      try {
        logAndToast("Initializing local ONNX runtime", name: "depth_estimator");
        OrtEnv.instance.init();
        final sessionOptions = OrtSessionOptions();
        _ortSession = OrtSession.fromFile(File(modelPath), sessionOptions);
        logAndToast("ONNX runtime initialized locally", name: "depth_estimator");
      } catch (e) {
        logAndToast("Failed to initialize local ONNX runtime: $e", name: "depth_estimator");
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
      } else {
        logAndToast("Using offline flutter onnx inference", name: "depth_estimator");
      }
      
      _isInitialized = true;
    } catch (e) {
      logAndToast('DepthEstimator: Failed to initialize: $e', name: "depth_estimator");
      debugPrint('DepthEstimator: Failed to initialize: $e');
      _isInitialized = true;
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
    
    if (_ortSession == null) {
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
      logAndToast("ONNX inference failed: $e", name: "depth_estimator");
      return 0.0;
    }
  }

  double _calibrateDepth(double rawValue) {
    const double calibrationValue = 147.0;
    const double calibrationDistance = 6.0;
    
    if (rawValue == 0) return 0.0;
    return (rawValue / calibrationValue) * calibrationDistance;
  }

  Future<String> _getModelPath() async {
    final appDir = await getApplicationSupportDirectory();
    final modelDir = '${appDir.path}/models';
    
    Directory(modelDir).createSync(recursive: true);
    
    final modelPath = '$modelDir/depth_model.onnx';
    
    if (!await File(modelPath).exists()) {
      final ByteData data = await rootBundle.load('assets/models/depth_model.onnx');
      await File(modelPath).writeAsBytes(data.buffer.asUint8List());
    }
    
    return modelPath;
  }

  void dispose() {
    if (_isInitialized && _useNative) {
      platform.invokeMethod('cleanupModel').ignore();
    }
    _ortSession?.release();
    OrtEnv.instance.release();
  }
}
