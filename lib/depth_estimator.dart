import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class DepthEstimator {
  static const platform = MethodChannel('com.depth.app/depth');
  
  const DepthEstimator();

  Future<void> initialize() async {
    try {
      final String modelPath = await _getModelPath();
      await platform.invokeMethod('initializeModel', {'modelPath': modelPath});
    } catch (e) {
      throw Exception('Failed to initialize depth model: $e');
    }
  }

  Future<double> estimateDepth(Uint8List bboxBytes) async {
    try {
      final double rawDepth = await platform.invokeMethod<double>(
        'estimateDepth',
        {'imageBytes': bboxBytes},
      ) ?? 0.0;
      
      return _calibrateDepth(rawDepth);
    } catch (e) {
      throw Exception('Depth estimation failed: $e');
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
    
    Directory(modelDir).createSync(recursive: true, exclusive: false);
    
    final modelPath = '$modelDir/depth_model.onnx';
    
    if (!await File(modelPath).exists()) {
      final ByteData data = await rootBundle.load('assets/models/depth_model.onnx');
      await File(modelPath).writeAsBytes(data.buffer.asUint8List());
    }
    
    return modelPath;
  }

  void dispose() {
    platform.invokeMethod('cleanupModel').ignore();
  }
}
