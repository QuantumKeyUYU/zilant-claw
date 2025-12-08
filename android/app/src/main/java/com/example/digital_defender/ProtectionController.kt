package com.example.digital_defender

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.atomic.AtomicLong

enum class ProtectionState {
    OFF,
    STARTING,
    ON,
    ERROR,
    RECONNECTING
}

object ProtectionController {
    private const val WATCHDOG_INTERVAL_MS = 10_000L
    private const val COMMAND_TIMEOUT_MS = 8_000L

    private val mainHandler = Handler(Looper.getMainLooper())
    private val lastAliveAt = AtomicLong(0)

    @Volatile
    private var appContext: Context? = null

    @Volatile
    private var currentState: ProtectionState = ProtectionState.OFF

    @Volatile
    private var lastStartRequestedAt = 0L

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    fun init(context: Context) {
        appContext = context.applicationContext
        scheduleWatchdog()
    }

    fun startProtection() {
        val context = appContext ?: return
        if (currentState == ProtectionState.ON) {
            emitState()
            return
        }
        if (currentState == ProtectionState.STARTING && !isCommandTimedOut()) {
            emitState()
            return
        }
        currentState = ProtectionState.STARTING
        lastStartRequestedAt = SystemClock.elapsedRealtime()
        lastAliveAt.set(lastStartRequestedAt)
        emitState()

        val intent = Intent(context, DigitalDefenderVpnService::class.java)
        ContextCompat.startForegroundService(context, intent)
    }

    fun stopProtection() {
        val context = appContext ?: return
        currentState = ProtectionState.OFF
        emitState()

        val stopIntent = Intent(context, DigitalDefenderVpnService::class.java).apply {
            action = DigitalDefenderVpnService.ACTION_STOP
        }
        ContextCompat.startForegroundService(context, stopIntent)
    }

    fun applyProtectionMode() {
        val context = appContext ?: return
        val intent = Intent(context, DigitalDefenderVpnService::class.java).apply {
            action = DigitalDefenderVpnService.ACTION_APPLY_PROTECTION_MODE
        }
        ContextCompat.startForegroundService(context, intent)
    }

    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
        emitState()
    }

    fun onServiceStarted() {
        currentState = ProtectionState.ON
        lastAliveAt.set(SystemClock.elapsedRealtime())
        emitState()
    }

    fun onServiceError() {
        currentState = ProtectionState.ERROR
        emitState()
    }

    fun onServiceStopped() {
        currentState = ProtectionState.OFF
        emitState()
    }

    fun reportAlive() {
        lastAliveAt.set(SystemClock.elapsedRealtime())
    }

    private fun scheduleWatchdog() {
        mainHandler.postDelayed({
            try {
                checkWatchdog()
            } finally {
                scheduleWatchdog()
            }
        }, WATCHDOG_INTERVAL_MS)
    }

    private fun checkWatchdog() {
        val context = appContext ?: return
        val now = SystemClock.elapsedRealtime()
        val last = lastAliveAt.get()
        val staleThreshold = WATCHDOG_INTERVAL_MS * 3
        if (currentState == ProtectionState.ON && last > 0 && now - last > staleThreshold) {
            currentState = ProtectionState.RECONNECTING
            emitState()
            val intent = Intent(context, DigitalDefenderVpnService::class.java).apply {
                action = DigitalDefenderVpnService.ACTION_STOP
            }
            ContextCompat.startForegroundService(context, intent)
            mainHandler.postDelayed({ startProtection() }, 1500)
        }
    }

    private fun isCommandTimedOut(): Boolean {
        val now = SystemClock.elapsedRealtime()
        return now - lastStartRequestedAt > COMMAND_TIMEOUT_MS
    }

    private fun emitState() {
        mainHandler.post {
            eventSink?.success(currentState.name)
        }
    }
}
