package com.anajak.anajak_travel

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.pm.PackageManager

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "anajak/maps_config")
            .setMethodCallHandler { call, result ->
                if (call.method == "configured") {
                    val info = packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
                    val key = info.metaData?.getString("com.google.android.geo.API_KEY") ?: ""
                    result.success(key.isNotBlank() && !key.startsWith("YOUR_"))
                } else result.notImplemented()
            }
    }
}
