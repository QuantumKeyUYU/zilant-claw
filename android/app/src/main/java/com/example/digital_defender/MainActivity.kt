package com.example.digital_defender

import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import android.util.Log
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
        if (pendingResult != null) {
            result.error("pending", "VPN permission request is already in progress", null)
            return
        }

        val intent = VpnService.prepare(this)
        if (intent != null) {
            pendingResult = result
            Log.i(TAG, "Requesting VPN permission")
            startActivityForResult(intent, vpnRequestCode)
            return
        }
        try {
            startVpnService()
            result.success(null)
        } catch (e: Exception) {
            result.error("start_failed", "Failed to start VPN service: ${e.message}", null)
        }
    }

    private fun stopVpn(result: MethodChannel.Result) {
        try {
            val stopIntent = Intent(this, DigitalDefenderVpnService::class.java)
            stopService(stopIntent)
            result.success(null)
        } catch (e: Exception) {
            result.error("stop_failed", "Failed to stop VPN service: ${e.message}", null)
        }
    }

    private fun startVpnService() {
        val intent = Intent(this, DigitalDefenderVpnService::class.java)
        ContextCompat.startForegroundService(this, intent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == vpnRequestCode) {
            if (resultCode == RESULT_OK) {
                Log.i(TAG, "VPN permission granted")
                startVpnService()
                pendingResult?.success(null)
            } else {
                Log.w(TAG, "VPN permission denied")
                pendingResult?.error("denied", "VPN permission denied", null)
            }
            pendingResult = null
        }
    }

    companion object {
        private const val TAG = "MainActivity"
    }
}
