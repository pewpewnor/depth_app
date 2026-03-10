import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

class DepthEstimator {
  static const platform = MethodChannel('com.depth.app/depth');
  static const String _serverUrl = 'http://127.0.0.1:5000';
  
  bool _isInitialized = false;
  bool _platformSupported = false;
  bool _useNative = false;

  DepthEstimator();

  Future<void> initialize() async {
    try {
      _platformSupported = Platform.isAndroid || Platform.isIOS;
      
      if (!_platformSupported) {
        _isInitialized = await _checkServerAvailable();
        if (_isInitialized) {
          debugPrint('DepthEstimator: Using Python server');
        } else {
          debugPrint('DepthEstimator: Running in demo mode');
          _isInitialized = true;
        }
        return;
      }

      final String modelPath = await _getModelPath();
      await platform.invokeMethod('initializeModel', {'modelPath': modelPath});
      _useNative = true;
      _isInitialized = true;
    } catch (e) {
      debugPrint('DepthEstimator: Failed to initialize: $e');
      _isInitialized = true;
    }
  }

  Future<bool> _checkServerAvailable() async {
    try {
      final response = await http.get(
        Uri.parse('$_serverUrl/health'),
      ).timeout(const Duration(seconds: 2));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<double> estimateDepth(Uint8List bboxBytes) async {
    if (!_isInitialized) {
      return 1.0;
    }

    if (_useNative || (Platform.isAndroid || Platform.isIOS)) {
      return _estimateDepthNative(bboxBytes);
    } else {
      return _estimateDepthServer(bboxBytes);
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

  Future<double> _estimateDepthServer(Uint8List bboxBytes) async {
    try {
      final base64Image = base64Encode(bboxBytes);
      final response = await http.post(
        Uri.parse('$_serverUrl/estimate_depth'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'image': base64Image}),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return (json['depth'] as num).toDouble();
      }
      return 0.0;
    } catch (e) {
      debugPrint('DepthEstimator: Server depth estimation failed: $e');
      return 1.0;
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
    if (_isInitialized && _platformSupported) {
      platform.invokeMethod('cleanupModel').ignore();
    }
  }
}
