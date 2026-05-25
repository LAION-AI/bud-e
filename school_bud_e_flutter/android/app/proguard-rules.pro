# Keep ONNX Runtime classes — JNI needs them at runtime
-keep class ai.onnxruntime.** { *; }
-keepclassmembers class ai.onnxruntime.** { *; }

# Keep the native methods
-keepclasseswithmembers class * {
    native <methods>;
}
