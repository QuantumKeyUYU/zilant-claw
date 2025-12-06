package com.example.digital_defender

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat

class DigitalDefenderVpnService : VpnService() {
    private var vpnInterface: ParcelFileDescriptor? = null

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "onCreate")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.i(TAG, "onStartCommand")
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
        startProtection()
        return START_STICKY
    }

    override fun onRevoke() {
        Log.w(TAG, "onRevoke")
        stopProtection()
        super.onRevoke()
    }

    override fun onDestroy() {
        Log.i(TAG, "onDestroy")
        stopProtection()
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                getString(R.string.vpn_channel_name),
                NotificationManager.IMPORTANCE_LOW
            )
            channel.description = getString(R.string.vpn_channel_description)
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.vpn_channel_name))
            .setContentText(getString(R.string.vpn_channel_description))
            .setSmallIcon(android.R.drawable.stat_sys_warning)
            .setOngoing(true)
            .build()
    }

    private fun startProtection() {
        if (vpnInterface != null) {
            Log.i(TAG, "VPN already active")
            return
        }
        try {
            val builder = Builder()
                .setSession("Digital Defender")
                .setBlocking(true)
                .addAddress("10.0.0.2", 32)
                .addDnsServer("1.1.1.1")
                .addDnsServer("8.8.8.8")
                .addRoute("0.0.0.0", 0)

            vpnInterface = builder.establish()
            if (vpnInterface == null) {
                Log.e(TAG, "Failed to establish VPN interface")
                stopSelf()
            } else {
                Log.i(TAG, "VPN interface established")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error starting VPN", e)
            stopProtection()
            stopSelf()
        }
    }

    private fun stopProtection() {
        Log.i(TAG, "Stopping protection")
        try {
            vpnInterface?.close()
        } catch (e: Exception) {
            Log.w(TAG, "Error closing VPN interface", e)
        } finally {
            vpnInterface = null
        }
    }

    companion object {
        private const val CHANNEL_ID = "digital_defender_vpn"
        private const val NOTIFICATION_ID = 1
        private const val TAG = "DigitalDefenderVpnService"
    }
}
