package com.example.depth_app

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import ai.onnxruntime.OnnxTensor
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.depth.app/depth"
    private var ortSession: OrtSession? = null
    private var ortEnvironment: OrtEnvironment? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initializeModel" -> {
                    val modelPath = call.argument<String>("modelPath")
                    try {
                        initializeDepthModel(modelPath)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("INIT_ERROR", e.message, null)
                    }
                }
                "estimateDepth" -> {
                    val imageBytes = call.argument<ByteArray>("imageBytes")
                    try {
                        val depth = estimateDepthFromBytes(imageBytes)
                        result.success(depth)
                    } catch (e: Exception) {
                        result.error("ESTIMATE_ERROR", e.message, null)
                    }
                }
                "cleanupModel" -> {
                    cleanupModel()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun initializeDepthModel(modelPath: String?) {
        if (modelPath == null || !File(modelPath).exists()) {
            throw Exception("Model file not found: $modelPath")
        }

        try {
            ortEnvironment = OrtEnvironment.getEnvironment()
            ortSession = ortEnvironment!!.createSession(modelPath)
            println("ONNX Runtime model initialized successfully")
        } catch (e: Exception) {
            throw Exception("Failed to initialize model: ${e.message}")
        }
    }

    private fun estimateDepthFromBytes(imageBytes: ByteArray?): Double {
        if (imageBytes == null || ortSession == null || ortEnvironment == null) {
            return 0.0
        }

        try {
            val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
            val resized = Bitmap.createScaledBitmap(bitmap, 518, 518, true)

            val floatArray = FloatArray(3 * 518 * 518)
            val pixelData = IntArray(518 * 518)
            resized.getPixels(pixelData, 0, 518, 0, 0, 518, 518)

            var idx = 0
            for (pixel in pixelData) {
                val r = ((pixel shr 16) and 0xFF) / 255.0f
                val g = ((pixel shr 8) and 0xFF) / 255.0f
                val b = (pixel and 0xFF) / 255.0f

                floatArray[idx] = (r - 0.485f) / 0.229f
                floatArray[idx + 518 * 518] = (g - 0.456f) / 0.224f
                floatArray[idx + 2 * 518 * 518] = (b - 0.406f) / 0.225f
                idx++
            }

            // Create input tensor directly (no allocator needed for 1.17.1)
            val shape = longArrayOf(1, 3, 518, 518)
            val inputTensor = OnnxTensor.createTensor(ortEnvironment!!, floatArray, shape)

            // Run inference
            val results = ortSession!!.run(mapOf("pixel_values" to inputTensor))
            
            // Extract output
            val output = results[0].value as FloatArray
            val depthValue = output.maxOrNull() ?: 0.0f
            
            // Cleanup
            inputTensor.close()

            return depthValue.toDouble()
        } catch (e: Exception) {
            throw Exception("Depth estimation failed: ${e.message}")
        }
    }

    private fun cleanupModel() {
        ortSession?.close()
        ortEnvironment?.close()
    }
}



