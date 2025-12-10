package com.example.digital_defender

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import org.json.JSONArray
import org.json.JSONObject
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetSocketAddress
import java.net.SocketTimeoutException
import kotlin.concurrent.thread

class DigitalDefenderVpnService : VpnService() {
    private var vpnInterface: ParcelFileDescriptor? = null
    private var workerThread: Thread? = null
    private var worker: DnsVpnWorker? = null

    @Volatile
    private var running = false

    private val blocklist = DomainBlocklist
    private lateinit var preferences: SharedPreferences

    private var blockedCount: Long = 0
    private var sessionBlockedCount: Long = 0
    private var failOpenActive: Boolean = false

    private val upstreamServers = listOf(
        InetSocketAddress("1.1.1.1", 53),
        InetSocketAddress("8.8.8.8", 53)
    )

    override fun onCreate() {
        super.onCreate()
        preferences = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        Log.d(TAG, "onCreate")

        blocklist.init(this)
        maybeRefreshBlocklist()

        blockedCount = readBlockedCount(this)
        sessionBlockedCount = DigitalDefenderStats.readSessionBlockedCount(this)
        failOpenActive = DigitalDefenderStats.readFailOpenActive(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                Log.i(TAG, "Stopping service via ACTION_STOP")
                stopProtection()
                stopSelf()
                ProtectionController.onServiceStopped()
                return START_NOT_STICKY
            }

            ACTION_APPLY_PROTECTION_MODE -> {
                val wasRunning = preferences.getBoolean(KEY_PROTECTION_ENABLED, false)
                Log.i(TAG, "Applying new protection mode; was running: $wasRunning")

                if (wasRunning) stopProtection()

                blocklist.reloadForMode(this)
                maybeRefreshBlocklist()

                if (wasRunning) {
                    return try {
                        createNotificationChannel()
                        startForeground(NOTIFICATION_ID, buildNotification())
                        startProtection()
                        ProtectionController.onServiceStarted()
                        START_STICKY
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to restart VPN after mode change", e)
                        ProtectionController.onServiceError()
                        stopSelf()
                        START_NOT_STICKY
                    }
                }

                return START_NOT_STICKY
            }
        }

        return try {
            createNotificationChannel()
            startForeground(NOTIFICATION_ID, buildNotification())
            startProtection()
            ProtectionController.onServiceStarted()
            START_STICKY
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start VPN service", e)
            stopProtection()
            ProtectionController.onServiceError()
            stopSelf()
            START_NOT_STICKY
        }
    }

    override fun onRevoke() {
        stopProtection()
        super.onRevoke()
    }

    override fun onDestroy() {
        stopProtection()
        setProtectionEnabled(false)
        ProtectionController.onServiceStopped()
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

            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.vpn_channel_name))
            .setContentText(getString(R.string.vpn_channel_description))
            .setSmallIcon(android.R.drawable.stat_sys_warning)
            .setOngoing(true)
            .build()

    private fun startProtection() {
        if (vpnInterface != null && running) return

        try {
            val builder = Builder()
                .setSession("Digital Defender")
                .setBlocking(true)
                .addAddress("10.0.0.2", 32)
                .apply {
                    upstreamServers.forEach { server ->
                        addDnsServer(server.address)
                        addRoute(server.address.hostAddress, 32)
                    }
                }

            vpnInterface = builder.establish()

            if (vpnInterface == null) {
                setProtectionEnabled(false)
                ProtectionController.onServiceError()
                stopSelf()
                return
            }

            resetSessionCounters()
            setFailOpenActive(false)

            startWorker(vpnInterface!!)
            setProtectionEnabled(true)

        } catch (e: Exception) {
            stopProtection()
            setProtectionEnabled(false)
            ProtectionController.onServiceError()
            stopSelf()
        }
    }

    private fun startWorker(tunnel: ParcelFileDescriptor) {
        running = true
        worker = DnsVpnWorker(this, tunnel, blocklist, upstreamServers)
        workerThread = thread(start = true, name = "DnsVpnWorker") { worker?.run() }
    }

    private fun stopProtection() {
        running = false

        try {
            worker?.stop()
            workerThread?.interrupt()
            workerThread?.join(500)
        } catch (_: Exception) { }

        vpnInterface?.close()
        vpnInterface = null

        worker = null
        workerThread = null

        resetSessionCounters()
        setProtectionEnabled(false)
        setFailOpenActive(false)
    }

    private inner class DnsVpnWorker(
        private val vpnService: VpnService,
        private val tunInterface: ParcelFileDescriptor,
        private val blocklist: DomainBlocklist,
        private val upstreamServers: List<InetSocketAddress>
    ) {
        @Volatile
        private var active = true

        private var currentUpstreamIndex = 0
        private val input = FileInputStream(tunInterface.fileDescriptor)
        private val output = FileOutputStream(tunInterface.fileDescriptor)

        private val socket: DatagramSocket = DatagramSocket().apply {
            soTimeout = 3000
            vpnService.protect(this)
        }

        private var failOpen = failOpenActive
        private var consecutiveFailures = 0
        private var failureWindowStartMs = 0L

        fun run() {
            val buffer = ByteArray(32767)

            try {
                while (active && running) {
                    val length = try {
                        input.read(buffer)
                    } catch (_: Exception) {
                        break
                    }

                    if (length > 0) handlePacket(buffer, length)
                }
            } finally {
                cleanup()
            }
        }

        fun stop() {
            active = false
            socket.close()
        }

        private fun cleanup() {
            active = false
            try { socket.close() } catch (_: Exception) {}
            try { input.close() } catch (_: Exception) {}
            try { output.close() } catch (_: Exception) {}
            try { tunInterface.close() } catch (_: Exception) {}

            if (running) {
                running = false
                this@DigitalDefenderVpnService.stopSelf()
            }
        }

        private fun handlePacket(packet: ByteArray, length: Int) {
            if (length < 20) return

            val version = packet[0].toInt() ushr 4
            if (version != 4) return

            val ihl = (packet[0].toInt() and 0x0F) * 4
            if (length < ihl + 8) return

            val protocol = packet[9].toInt() and 0xFF
            if (protocol != 17) return

            val ipTotalLength = readUint16(packet, 2)
            val effectiveLength = minOf(length, ipTotalLength)

            if (DEBUG_DNS) {
                Log.d(TAG, "DNS packet... len=$effectiveLength")
            }

            val udpOffset = ihl
            val destPort = readUint16(packet, udpOffset + 2)
            if (destPort != 53) return

            val udpLength = readUint16(packet, udpOffset + 4)
            if (udpOffset + udpLength > effectiveLength) return

            val dnsOffset = udpOffset + 8
            val dnsLength = effectiveLength - dnsOffset
            if (dnsLength <= 0) return

            val query = extractQuery(packet, dnsOffset, dnsLength) ?: return forwardToUpstream(packet, length, ihl, dnsOffset, dnsLength)

            val domain = query.domain
            val eval = blocklist.evaluate(domain)

            val shouldBlock = !failOpen && eval.isBlocked

            if (shouldBlock) {
                recordBlockedDomain(domain)
                sendBlockedResponse(packet, ihl, dnsOffset, query.questionEnd)
            } else {
                forwardToUpstream(packet, length, ihl, dnsOffset, dnsLength)
            }
        }

        private fun forwardToUpstream(
            packet: ByteArray,
            length: Int,
            ihl: Int,
            dnsOffset: Int,
            dnsLength: Int
        ) {
            val dnsPayload = packet.copyOfRange(dnsOffset, dnsOffset + dnsLength)

            var attempts = 0
            while (attempts < upstreamServers.size) {
                val upstream = upstreamServers[currentUpstreamIndex]
                if (tryUpstream(upstream, dnsPayload, packet, ihl)) return
                currentUpstreamIndex = (currentUpstreamIndex + 1) % upstreamServers.size
                attempts++
            }

            recordUpstreamFailure()
        }

        private fun tryUpstream(upstream: InetSocketAddress, dnsPayload: ByteArray, packet: ByteArray, ihl: Int): Boolean {
            return try {
                socket.send(DatagramPacket(dnsPayload, dnsPayload.size, upstream))

                val buffer = ByteArray(4096)
                val resp = DatagramPacket(buffer, buffer.size)
                socket.receive(resp)

                recordUpstreamSuccess()

                val srcIp = packet.copyOfRange(12, 16)
                val destIp = packet.copyOfRange(16, 20)

                val response = buildIpUdpPacket(
                    resp.data,
                    resp.length,
                    destIp,
                    srcIp,
                    readUint16(packet, ihl + 2),
                    readUint16(packet, ihl)
                )

                output.write(response, 0, response.size)
                true

            } catch (_: Exception) {
                recordUpstreamFailure()
                false
            }
        }

        private fun recordUpstreamSuccess() {
            consecutiveFailures = 0
            failureWindowStartMs = 0L
            if (failOpen) {
                failOpen = false
                setFailOpenActive(false)
            }
        }

        private fun recordUpstreamFailure() {
            val now = System.currentTimeMillis()

            if (failureWindowStartMs == 0L || now - failureWindowStartMs > FAIL_OPEN_WINDOW_MS) {
                failureWindowStartMs = now
                consecutiveFailures = 1
            } else {
                consecutiveFailures++
            }

            if (!failOpen && consecutiveFailures >= FAIL_OPEN_THRESHOLD) {
                failOpen = true
                setFailOpenActive(true)
            }
        }

        private fun sendBlockedResponse(packet: ByteArray, ihl: Int, dnsOffset: Int, questionEnd: Int) {
            val qLen = questionEnd - (dnsOffset + 12)
            if (qLen < 0) return

            val dnsResponseLength = 12 + qLen
            val dnsResponse = ByteArray(dnsResponseLength)

            System.arraycopy(packet, dnsOffset, dnsResponse, 0, 2)

            val reqFlags = readUint16(packet, dnsOffset + 2)
            var respFlags = reqFlags or 0x8000
            respFlags = (respFlags and 0xFFF0) or 3

            writeUint16(dnsResponse, 2, respFlags)
            writeUint16(dnsResponse, 4, 1)
            writeUint16(dnsResponse, 6, 0)
            writeUint16(dnsResponse, 8, 0)
            writeUint16(dnsResponse, 10, 0)

            System.arraycopy(packet, dnsOffset + 12, dnsResponse, 12, qLen)

            val srcIp = packet.copyOfRange(12, 16)
            val destIp = packet.copyOfRange(16, 20)

            val response = buildIpUdpPacket(
                dnsResponse,
                dnsResponse.size,
                destIp,
                srcIp,
                readUint16(packet, ihl + 2),
                readUint16(packet, ihl)
            )

            output.write(response, 0, response.size)
        }

        private fun buildIpUdpPacket(
            payload: ByteArray,
            payloadLength: Int,
            srcIp: ByteArray,
            destIp: ByteArray,
            srcPort: Int,
            destPort: Int
        ): ByteArray {
            val ipHeaderLength = 20
            val udpHeaderLength = 8
            val totalLength = ipHeaderLength + udpHeaderLength + payloadLength

            val buffer = ByteArray(totalLength)

            buffer[0] = 0x45
            buffer[1] = 0
            writeUint16(buffer, 2, totalLength)
            writeUint16(buffer, 4, 0)
            writeUint16(buffer, 6, 0)

            buffer[8] = 64
            buffer[9] = 17

            System.arraycopy(srcIp, 0, buffer, 12, 4)
            System.arraycopy(destIp, 0, buffer, 16, 4)

            writeUint16(buffer, 10, computeChecksum(buffer, 0, ipHeaderLength))

            val udpOffset = ipHeaderLength
            writeUint16(buffer, udpOffset, srcPort)
            writeUint16(buffer, udpOffset + 2, destPort)
            writeUint16(buffer, udpOffset + 4, udpHeaderLength + payloadLength)
            writeUint16(buffer, udpOffset + 6, 0)

            System.arraycopy(payload, 0, buffer, udpOffset + udpHeaderLength, payloadLength)

            return buffer
        }

        private fun extractQuery(packet: ByteArray, offset: Int, length: Int): DnsQuery? {
            if (length < 12) return null

            val qdCount = readUint16(packet, offset + 4)
            if (qdCount < 1) return null

            val labels = mutableListOf<String>()
            val end = offset + length
            var pos = offset + 12

            while (pos < end) {
                val lenByte = packet[pos].toInt() and 0xFF
                pos++

                if (lenByte == 0) break
                if (pos + lenByte > end) return null

                val label = String(packet, pos, lenByte)
                labels.add(label)
                pos += lenByte
            }

            if (labels.isEmpty()) return null
            if (pos + 4 > end) return null

            val domain = labels.joinToString(".")
            return DnsQuery(domain.lowercase(), pos + 4)
        }

        private fun readUint16(data: ByteArray, offset: Int): Int =
            ((data[offset].toInt() and 0xFF) shl 8) or (data[offset + 1].toInt() and 0xFF)

        private fun writeUint16(buffer: ByteArray, offset: Int, value: Int) {
            buffer[offset] = (value shr 8).toByte()
            buffer[offset + 1] = (value and 0xFF).toByte()
        }

        private fun computeChecksum(buffer: ByteArray, offset: Int, length: Int): Int {
            var sum = 0
            var i = offset

            while (i < offset + length) {
                sum += ((buffer[i].toInt() and 0xFF) shl 8) or (buffer[i + 1].toInt() and 0xFF)
                while (sum > 0xFFFF) sum = (sum and 0xFFFF) + (sum ushr 16)
                i += 2
            }

            return sum.inv() and 0xFFFF
        }
    }

    data class DnsQuery(val domain: String, val questionEnd: Int)

    companion object {
        private const val CHANNEL_ID = "digital_defender_vpn"
        private const val NOTIFICATION_ID = 1
        internal const val TAG = "DigitalDefenderVpnService"

        // BuildConfig удалён — теперь используем простой флаг
        private const val DEBUG_DNS = false

        internal const val PREFS_NAME = "digital_defender_prefs"
        internal const val KEY_BLOCKED_COUNT = "blocked_count"
        internal const val KEY_SESSION_BLOCKED_COUNT = "session_blocked_count"
        internal const val KEY_FAIL_OPEN_ACTIVE = "fail_open_active"
        private const val KEY_LAST_BLOCKLIST_UPDATE = "last_blocklist_update"
        internal const val KEY_RECENT_BLOCKS = "recent_blocks"
        internal const val KEY_PROTECTION_ENABLED = "protection_enabled"

        private const val BLOCKLIST_REFRESH_INTERVAL_MS = 4 * 60 * 60 * 1000L

        const val ACTION_STOP = "com.example.digital_defender.STOP"
        const val ACTION_APPLY_PROTECTION_MODE =
            "com.example.digital_defender.APPLY_PROTECTION_MODE"

        private const val FAIL_OPEN_THRESHOLD = 5
        private const val FAIL_OPEN_WINDOW_MS = 15000L

        fun readBlockedCount(context: Context): Long =
            DigitalDefenderStats.readBlockedCount(context)
    }

    @Synchronized
    private fun recordBlockedDomain(domain: String) {
        val update = DigitalDefenderStats.recordBlock(this, domain)
        blockedCount = update.blockedTotal
        sessionBlockedCount = update.sessionBlocked
        Log.i(TAG, "Blocked domain: $domain")
    }

    private fun resetSessionCounters() {
        sessionBlockedCount = 0
        DigitalDefenderStats.resetSessionCount(this)
    }

    private fun setProtectionEnabled(enabled: Boolean) {
        preferences.edit().putBoolean(KEY_PROTECTION_ENABLED, enabled).apply()
    }

    private fun setFailOpenActive(active: Boolean) {
        failOpenActive = active
        preferences.edit().putBoolean(KEY_FAIL_OPEN_ACTIVE, active).apply()
    }

    private fun maybeRefreshBlocklist() {
        val now = System.currentTimeMillis()
        val lastUpdate = preferences.getLong(KEY_LAST_BLOCKLIST_UPDATE, 0L)

        if (now - lastUpdate < BLOCKLIST_REFRESH_INTERVAL_MS) return

        thread(name = "BlocklistRefresh", start = true) {
            val ok = blocklist.refreshFromNetwork(this)
            preferences.edit().putLong(KEY_LAST_BLOCKLIST_UPDATE, System.currentTimeMillis()).apply()

            if (ok) Log.i(TAG, "Blocklist refreshed")
            else Log.i(TAG, "Blocklist refresh failed — using existing list")
        }
    }
}

data class BlockedEntry(val domain: String, val timestamp: Long)

object DigitalDefenderStats {
    private const val MAX_RECENT = 100

    fun readBlockedCount(context: Context) =
        context.getSharedPreferences(DigitalDefenderVpnService.PREFS_NAME, Context.MODE_PRIVATE)
            .getLong(DigitalDefenderVpnService.KEY_BLOCKED_COUNT, 0L)

    fun readSessionBlockedCount(context: Context) =
        context.getSharedPreferences(DigitalDefenderVpnService.PREFS_NAME, Context.MODE_PRIVATE)
            .getLong(DigitalDefenderVpnService.KEY_SESSION_BLOCKED_COUNT, 0L)

    fun readFailOpenActive(context: Context) =
        context.getSharedPreferences(DigitalDefenderVpnService.PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(DigitalDefenderVpnService.KEY_FAIL_OPEN_ACTIVE, false)

    fun resetSessionCount(context: Context) {
        context.getSharedPreferences(DigitalDefenderVpnService.PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putLong(DigitalDefenderVpnService.KEY_SESSION_BLOCKED_COUNT, 0L)
            .apply()
    }

    data class StatsUpdate(val blockedTotal: Long, val sessionBlocked: Long)

    @Synchronized
    fun recordBlock(context: Context, domain: String): StatsUpdate {
        val prefs = context.getSharedPreferences(DigitalDefenderVpnService.PREFS_NAME, Context.MODE_PRIVATE)

        val total = prefs.getLong(DigitalDefenderVpnService.KEY_BLOCKED_COUNT, 0L) + 1
        val session = prefs.getLong(DigitalDefenderVpnService.KEY_SESSION_BLOCKED_COUNT, 0L) + 1

        val recent = loadRecent(prefs).apply {
            add(BlockedEntry(domain, System.currentTimeMillis()))
            if (size > MAX_RECENT) removeAt(0)
        }

        prefs.edit()
            .putLong(DigitalDefenderVpnService.KEY_BLOCKED_COUNT, total)
            .putLong(DigitalDefenderVpnService.KEY_SESSION_BLOCKED_COUNT, session)
            .putString(DigitalDefenderVpnService.KEY_RECENT_BLOCKS, serializeRecent(recent))
            .apply()

        return StatsUpdate(total, session)
    }

    @Synchronized
    fun getStatsJson(context: Context): String {
        val prefs = context.getSharedPreferences(DigitalDefenderVpnService.PREFS_NAME, Context.MODE_PRIVATE)

        val root = JSONObject()
        root.put("blockedCount", prefs.getLong(DigitalDefenderVpnService.KEY_BLOCKED_COUNT, 0L))
        root.put("sessionBlocked", prefs.getLong(DigitalDefenderVpnService.KEY_SESSION_BLOCKED_COUNT, 0L))
        root.put("running", prefs.getBoolean(DigitalDefenderVpnService.KEY_PROTECTION_ENABLED, false))
        root.put("mode", DomainBlocklist.getProtectionMode(context))
        root.put("failOpenActive", prefs.getBoolean(DigitalDefenderVpnService.KEY_FAIL_OPEN_ACTIVE, false))

        val recentArr = JSONArray()
        loadRecent(prefs).forEach { e ->
            val o = JSONObject()
            o.put("domain", e.domain)
            o.put("timestamp", e.timestamp)
            recentArr.put(o)
        }

        root.put("recent", recentArr)
        return root.toString()
    }

    @Synchronized
    fun resetStats(context: Context) {
        context.getSharedPreferences(DigitalDefenderVpnService.PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putLong(DigitalDefenderVpnService.KEY_BLOCKED_COUNT, 0L)
            .putLong(DigitalDefenderVpnService.KEY_SESSION_BLOCKED_COUNT, 0L)
            .putString(DigitalDefenderVpnService.KEY_RECENT_BLOCKS, JSONArray().toString())
            .apply()
    }

    @Synchronized
    fun clearRecent(context: Context) {
        context.getSharedPreferences(DigitalDefenderVpnService.PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(DigitalDefenderVpnService.KEY_RECENT_BLOCKS, JSONArray().toString())
            .apply()
    }

    private fun loadRecent(prefs: SharedPreferences): MutableList<BlockedEntry> {
        val text = prefs.getString(DigitalDefenderVpnService.KEY_RECENT_BLOCKS, "")
        if (text.isNullOrBlank()) return mutableListOf()

        return try {
            val arr = JSONArray(text)
            MutableList(arr.length()) { i ->
                val o = arr.getJSONObject(i)
                BlockedEntry(o.getString("domain"), o.getLong("timestamp"))
            }.toMutableList()
        } catch (_: Exception) {
            mutableListOf()
        }
    }

    private fun serializeRecent(list: List<BlockedEntry>): String {
        val arr = JSONArray()
        list.forEach {
            val o = JSONObject()
            o.put("domain", it.domain)
            o.put("timestamp", it.timestamp)
            arr.put(o)
        }
        return arr.toString()
    }
}
