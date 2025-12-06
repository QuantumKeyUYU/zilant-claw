package com.example.digital_defender

import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "digital_defender/protection"
    private val vpnRequestCode = 42

    private var pendingResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "android_start_protection" -> startVpn(result)
                    "android_stop_protection" -> stopVpn(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun startVpn(result: MethodChannel.Result) {
        val intent = VpnService.prepare(this)
        if (intent != null) {
            pendingResult = result
            startActivityForResult(intent, vpnRequestCode)
            return
        }
        startVpnService()
        result.success(null)
    }

    private fun stopVpn(result: MethodChannel.Result) {
        val stopIntent = Intent(this, DigitalDefenderVpnService::class.java)
        stopService(stopIntent)
        result.success(null)
    }

    private fun startVpnService() {
        val intent = Intent(this, DigitalDefenderVpnService::class.java)
        ContextCompat.startForegroundService(this, intent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == vpnRequestCode) {
            if (resultCode == RESULT_OK) {
                startVpnService()
                pendingResult?.success(null)
            } else {
                pendingResult?.error("denied", "VPN permission denied", null)
            }
            pendingResult = null
        }
    }
}
