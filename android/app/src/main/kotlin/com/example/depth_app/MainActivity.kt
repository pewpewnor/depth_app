package com.example.depth_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import ai.onnxruntime.OnnxTensor
import java.io.File
import java.nio.FloatBuffer

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
                    val frameWidth = call.argument<Int>("frameWidth") ?: 1080
                    val frameHeight = call.argument<Int>("frameHeight") ?: 1920
                    try {
                        val depth = estimateDepthFromBytes(imageBytes, frameWidth, frameHeight)
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

    private fun estimateDepthFromBytes(imageBytes: ByteArray?, frameWidth: Int, frameHeight: Int): Double {
        if (imageBytes == null || ortSession == null || ortEnvironment == null) {
            return 0.0
        }

        try {
            // imageBytes is raw RGB data from camera frame, not a JPEG/PNG
            val expectedRgbSize = frameWidth * frameHeight * 3
            
            if (imageBytes.size != expectedRgbSize) {
                println("ONNX: Invalid image size: expected $expectedRgbSize, got ${imageBytes.size}, using frameWidth=$frameWidth, frameHeight=$frameHeight")
                throw Exception("Invalid image size: expected $expectedRgbSize, got ${imageBytes.size}")
            }

            // Resize raw RGB data to 518x518
            val targetSize = 518
            val floatArray = FloatArray(3 * targetSize * targetSize)

            // ImageNet normalization required by DA3METRIC-LARGE
            val imgMean = floatArrayOf(0.485f, 0.456f, 0.406f)
            val imgStd  = floatArrayOf(0.229f, 0.224f, 0.225f)

            // Nearest neighbor scaling with ImageNet normalization
            for (c in 0 until 3) {
                for (y in 0 until targetSize) {
                    for (x in 0 until targetSize) {
                        val srcX = (x * frameWidth / targetSize).coerceIn(0, frameWidth - 1)
                        val srcY = (y * frameHeight / targetSize).coerceIn(0, frameHeight - 1)
                        val srcIdx = (srcY * frameWidth + srcX) * 3 + c

                        val dstIdx = c * (targetSize * targetSize) + y * targetSize + x
                        val pixel = (imageBytes[srcIdx].toInt() and 0xFF) / 255.0f
                        floatArray[dstIdx] = (pixel - imgMean[c]) / imgStd[c]
                    }
                }
            }

            val shape = longArrayOf(1L, 3L, targetSize.toLong(), targetSize.toLong())
            val floatBuffer = FloatBuffer.wrap(floatArray)
            val inputTensor = OnnxTensor.createTensor(ortEnvironment!!, floatBuffer, shape)

            println("ONNX: Running inference with input shape: ${shape.contentToString()}")
            val results = ortSession!!.run(mapOf("image" to inputTensor))
            
            println("ONNX: Got ${results.size()} output tensors")
            
            // Output tensor is [1, 518, 518]
            val outputValue = results[0]?.value
            if (outputValue == null) {
                println("ONNX: Output is null")
                return 0.0
            }
            
            println("ONNX: Output type: ${outputValue::class.simpleName}")
            
            val flatOutput = when (outputValue) {
                is FloatArray -> {
                    println("ONNX: Output is FloatArray of size ${outputValue.size}")
                    outputValue
                }
                is Array<*> -> {
                    println("ONNX: Output is Array (4D for DA3METRIC-LARGE)")
                    // Recursively flatten to handle [1, 1, H, W] 4D output
                    val flattened = mutableListOf<Float>()
                    fun flatten(arr: Array<*>) {
                        for (item in arr) {
                            when (item) {
                                is FloatArray -> flattened.addAll(item.toList())
                                is Array<*> -> flatten(item)
                            }
                        }
                    }
                    flatten(outputValue)
                    flattened.toFloatArray()
                }
                else -> {
                    println("ONNX: Unknown output type")
                    return 0.0
                }
            }
            
            if (flatOutput.isEmpty()) {
                println("ONNX: Flat output is empty")
                return 0.0
            }
            
            // Find center region in flat array
            // Output is [1, 518, 518] = flat array of 268324 elements
            // Center region: 118x118 pixels in the middle (for 120x120 bbox in original frame)
            val bboxSize120 = 120
            val centerRegionSize = (bboxSize120 * targetSize) / frameWidth
            val centerStart = (targetSize - centerRegionSize) / 2
            val centerEnd = centerStart + centerRegionSize
            
            var centerDepthSum = 0.0f
            var centerPixelCount = 0
            var minDepth = Float.MAX_VALUE
            var maxDepth = Float.MIN_VALUE
            
            // Find min and max for normalization
            for (value in flatOutput) {
                if (value < minDepth) minDepth = value
                if (value > maxDepth) maxDepth = value
            }
            
            println("ONNX: Min=$minDepth, Max=$maxDepth")
            
            // Extract center region
            for (y in centerStart until centerEnd) {
                for (x in centerStart until centerEnd) {
                    val idx = 0 * (targetSize * targetSize) + y * targetSize + x
                    if (idx < flatOutput.size) {
                        centerDepthSum += flatOutput[idx]
                        centerPixelCount++
                    }
                }
            }
            
            // Calculate average depth in center region
            val centerAverageDepth = if (centerPixelCount > 0) (centerDepthSum / centerPixelCount) else 0.0f
            
            println("ONNX: Center depth sum=$centerDepthSum, count=$centerPixelCount, avg=$centerAverageDepth")
            
            // DA3METRIC-LARGE outputs depth directly in meters — no normalization needed
            println("ONNX: Center depth (meters)=$centerAverageDepth")

            inputTensor.close()

            return centerAverageDepth.toDouble()
        } catch (e: Exception) {
            println("ONNX: Exception during depth estimation: ${e.message}")
            e.printStackTrace()
            throw Exception("Depth estimation failed: ${e.message}")
        }
    }

    private fun cleanupModel() {
        ortSession?.close()
        ortEnvironment?.close()
    }
}