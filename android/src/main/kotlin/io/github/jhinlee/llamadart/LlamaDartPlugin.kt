package io.github.jhinlee.llama_dart

import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel

/**
 * LlamaDartPlugin
 *
 * This plugin provides native library support for llama_dart.
 * The native libraries are automatically copied to jniLibs during build.
 */
class LlamaDartPlugin: FlutterPlugin {
    private lateinit var channel : MethodChannel

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "llama_dart")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                // Add native method handlers if needed
                else -> result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
