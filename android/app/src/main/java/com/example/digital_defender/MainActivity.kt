package com.example.digital_defender

import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import android.util.Log
import android.widget.Toast
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "digital_defender/protection"
    private val statsChannel = "digital_defender/stats"
    private val eventsChannel = "digital_defender/protection_events"
    private val vpnRequestCode = 42

    private var pendingResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ProtectionController.init(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "android_start_protection" -> startVpn(result)
                    "android_stop_protection" -> stopVpn(result)
                    "android_get_blocked_count" -> getBlockedCount(result)
                    "setProtectionMode" -> setProtectionMode(call, result)
                    "getProtectionMode" -> getProtectionMode(result)
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, statsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getStats" -> getStats(result)
                    "resetStats" -> resetStats(result)
                    "clearRecent" -> clearRecent(result)
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventsChannel)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    ProtectionController.setEventSink(events)
                }

                override fun onCancel(arguments: Any?) {
                    ProtectionController.setEventSink(null)
                }
            })
    }

    private fun startVpn(result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("pending", "VPN permission request is already in progress", null)
            return
        }

        val intent = VpnService.prepare(this)
        if (intent != null) {
            pendingResult = result
            Log.d(TAG, "Requesting VPN permission")
            startActivityForResult(intent, vpnRequestCode)
            return
        }
        try {
            Log.d(TAG, "VPN permission already granted, starting service")
            startVpnService()
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start VPN without permission dialog", e)
            showToast(getString(R.string.vpn_start_failed))
            result.error("start_failed", "Failed to start VPN service: ${e.message}", null)
        }
    }

    private fun stopVpn(result: MethodChannel.Result) {
        try {
            ProtectionController.stopProtection()
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to stop VPN service", e)
            showToast(getString(R.string.vpn_stop_failed))
            result.error("stop_failed", "Failed to stop VPN service: ${e.message}", null)
        }
    }

    private fun setProtectionMode(call: MethodCall, result: MethodChannel.Result) {
        try {
            val requested = call.argument<String>("mode") ?: DomainBlocklist.MODE_STANDARD
            val appliedMode = DomainBlocklist.setProtectionMode(this, requested)
            ProtectionController.applyProtectionMode()
            showToast(getString(R.string.protection_mode_changed, modeLabel(appliedMode)))
            result.success(appliedMode)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set protection mode", e)
            result.error("set_mode_failed", "Failed to set protection mode: ${e.message}", null)
        }
    }

    private fun getProtectionMode(result: MethodChannel.Result) {
        try {
            result.success(DomainBlocklist.getProtectionMode(this))
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get protection mode", e)
            result.error("get_mode_failed", "Failed to get protection mode", null)
        }
    }

    private fun modeLabel(mode: String): String {
        return when (mode.lowercase()) {
            DomainBlocklist.MODE_LIGHT -> getString(R.string.protection_mode_light)
            DomainBlocklist.MODE_STRICT -> getString(R.string.protection_mode_strict)
            else -> getString(R.string.protection_mode_standard)
        }
    }

    private fun startVpnService() {
        Log.d(TAG, "Starting DigitalDefenderVpnService via ProtectionController")
        ProtectionController.startProtection()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == vpnRequestCode) {
            if (resultCode == RESULT_OK) {
                Log.d(TAG, "VPN permission granted")
                try {
                    startVpnService()
                    pendingResult?.success(null)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to start VPN after permission granted", e)
                    showToast(getString(R.string.vpn_start_failed))
                    pendingResult?.error("start_failed", "Failed to start VPN service: ${e.message}", null)
                }
            } else {
                Log.w(TAG, "VPN permission denied")
                showToast(getString(R.string.vpn_permission_denied))
                pendingResult?.error("denied", "VPN permission denied", null)
            }
            pendingResult = null
        }
    }

    private fun getBlockedCount(result: MethodChannel.Result) {
        try {
            result.success(DigitalDefenderVpnService.readBlockedCount(this))
        } catch (e: Exception) {
            Log.e(TAG, "Failed to read blocked count", e)
            result.error("read_failed", "Failed to read blocked count", null)
        }
    }

    private fun getStats(result: MethodChannel.Result) {
        try {
            result.success(DigitalDefenderStats.getStatsJson(this))
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get stats", e)
            result.error("stats_failed", "Failed to get stats: ${e.message}", null)
        }
    }

    private fun resetStats(result: MethodChannel.Result) {
        try {
            DigitalDefenderStats.resetStats(this)
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to reset stats", e)
            result.error("reset_failed", "Failed to reset stats: ${e.message}", null)
        }
    }

    private fun clearRecent(result: MethodChannel.Result) {
        try {
            DigitalDefenderStats.clearRecent(this)
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to clear recent stats", e)
            result.error("clear_recent_failed", "Failed to clear recent stats: ${e.message}", null)
        }
    }

    private fun showToast(message: String) {
        runOnUiThread {
            Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
        }
    }

    companion object {
        private const val TAG = "MainActivity"
    }
}
