import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class DepthEstimator {
  static const platform = MethodChannel('com.depth.app/depth');
  
  bool _isInitialized = false;
  bool _useNative = false;

  DepthEstimator();

  Future<void> initialize() async {
    try {
      final bool isNativePlatform = Platform.isAndroid || Platform.isIOS;
      
      if (isNativePlatform) {
        final String modelPath = await _getModelPath();
        await platform.invokeMethod('initializeModel', {'modelPath': modelPath});
        _useNative = true;
      }
      
      _isInitialized = true;
    } catch (e) {
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
    
    int sum = 0;
    for (int i = 0; i < bboxBytes.length; i++) {
      sum += bboxBytes[i];
    }
    
    double mean = sum.toDouble() / bboxBytes.length;
    double normalized = (mean / 255.0 * 255.0).clamp(0, 255);
    
    return _calibrateDepth(normalized);
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
  }
}
