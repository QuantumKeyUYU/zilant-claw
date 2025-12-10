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
                if (wasRunning) {
                    stopProtection()
                }
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

        Log.d(TAG, "onStartCommand: starting foreground with type specialUse")
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
        Log.w(TAG, "onRevoke")
        stopProtection()
        super.onRevoke()
    }

    override fun onDestroy() {
        Log.d(TAG, "onDestroy")
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
        if (vpnInterface != null && running) {
            Log.d(TAG, "VPN already active")
            return
        }
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
                Log.e(TAG, "Failed to establish VPN interface")
                setProtectionEnabled(false)
                ProtectionController.onServiceError()
                stopSelf()
            } else {
                Log.d(TAG, "VPN interface established")
                resetSessionCounters()
                setFailOpenActive(false)
                startWorker(vpnInterface!!)
                setProtectionEnabled(true)
                Log.i(TAG, "VPN started")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error starting VPN", e)
            stopProtection()
            setProtectionEnabled(false)
            ProtectionController.onServiceError()
            stopSelf()
        }
    }

    private fun startWorker(tunnel: ParcelFileDescriptor) {
        running = true
        worker = DnsVpnWorker(this, tunnel, blocklist, upstreamServers)
        workerThread = thread(start = true, name = "DnsVpnWorker") {
            worker?.run()
        }
    }

    private fun stopProtection() {
        if (running || vpnInterface != null) {
            Log.i(TAG, "VPN stopped")
        }
        running = false
        try {
            worker?.stop()
            workerThread?.interrupt()
            workerThread?.join(500)
            workerThread = null
            vpnInterface?.close()
            stopForeground(true)
        } catch (e: Exception) {
            Log.w(TAG, "Error closing VPN interface", e)
        } finally {
            worker = null
            vpnInterface = null
            resetSessionCounters()
            setProtectionEnabled(false)
            setFailOpenActive(false)
            ProtectionController.onServiceStopped()
        }
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
            if (!vpnService.protect(this)) {
                Log.w(TAG, "Failed to protect upstream DNS socket; traffic may loop through the VPN")
            }
        }
        private var failOpen = failOpenActive
        private var consecutiveFailures = 0
        private var failureWindowStartMs = 0L

        fun run() {
            val buffer = ByteArray(32767)
            try {
                while (active && running) {
                    try {
                        ProtectionController.reportAlive()
                        val length = input.read(buffer)
                        if (length <= 0) continue
                        handlePacket(buffer, length)
                    } catch (e: SocketTimeoutException) {
                        continue
                    } catch (e: IOException) {
                        if (active) {
                            Log.e(TAG, "Error processing VPN traffic", e)
                        }
                        break
                    } catch (e: Exception) {
                        Log.e(TAG, "Error processing VPN traffic", e)
                        break
                    }
                }
            } finally {
                cleanup()
            }
        }

        private fun cleanup() {
            active = false
            try {
                socket.close()
            } catch (e: Exception) {
                Log.w(TAG, "Error closing socket", e)
            }
            try {
                input.close()
            } catch (e: Exception) {
                Log.w(TAG, "Error closing input", e)
            }
            try {
                output.close()
            } catch (e: Exception) {
                Log.w(TAG, "Error closing output", e)
            }
            try {
                tunInterface.close()
            } catch (e: Exception) {
                Log.w(TAG, "Error closing tun interface", e)
            }

            if (running) {
                Log.w(TAG, "Worker stopped unexpectedly; requesting service shutdown")
                running = false
                this@DigitalDefenderVpnService.stopSelf()
            }
        }

        fun stop() {
            active = false
            socket.close()
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
                Log.d(
                    TAG,
                    "DNS packet received: version=$version ipLen=$effectiveLength srcPort=${readUint16(packet, ihl)} destPort=${readUint16(packet, ihl + 2)}"
                )
            }

            val udpOffset = ihl
            val srcPort = readUint16(packet, udpOffset)
            val destPort = readUint16(packet, udpOffset + 2)
            if (destPort != 53) return

            val udpLength = readUint16(packet, udpOffset + 4)
            if (udpLength < 8) return
            if (udpOffset + udpLength > effectiveLength) return

            val dnsOffset = udpOffset + 8
            val dnsLength = effectiveLength - dnsOffset
            if (dnsLength <= 0) return
            if (dnsLength > 1500) {
                forwardToUpstream(packet, length, ihl, srcPort, destPort, dnsOffset, dnsLength)
                return
            }

            val query = extractQuery(packet, dnsOffset, dnsLength)
            if (query == null) {
                if (DEBUG_DNS) {
                    Log.d(TAG, "DNS query: domain=<parse_error> decision=PARSE_ERROR")
                }
                forwardToUpstream(packet, length, ihl, srcPort, destPort, dnsOffset, dnsLength)
                return
            }

            val domain = query.domain
            val evaluation = blocklist.evaluate(domain)
            val mode = evaluation.mode
            val allowedByPolicy = evaluation.allowedRule != null
            val shouldBlock = !failOpen && evaluation.isBlocked
            if (shouldBlock) {
                if (DEBUG_DNS) {
                    Log.d(
                        TAG,
                        "DNS query: domain=$domain decision=BLOCKED mode=$mode reason=${evaluation.blockedMatch?.category}:${evaluation.blockedMatch?.rule}"
                    )
                }
                recordBlockedDomain(domain)
                sendBlockedResponse(packet, ihl, srcPort, destPort, dnsOffset, query.questionEnd)
            } else {
                if (DEBUG_DNS) {
                    val decision = when {
                        shouldBlock -> "BLOCKED"
                        failOpen -> "ALLOWED_FAILOPEN"
                        else -> "ALLOWED"
                    }
                    val reason = when {
                        allowedByPolicy -> "allowlist:${evaluation.allowedRule}"
                        evaluation.blockedMatch != null -> "blocked:${evaluation.blockedMatch.category}:${evaluation.blockedMatch.rule}"
                        failOpen -> "fail-open"
                        else -> "not_listed"
                    }
                    Log.d(TAG, "DNS query: domain=$domain decision=$decision mode=$mode reason=$reason")
                }
                forwardToUpstream(packet, length, ihl, srcPort, destPort, dnsOffset, dnsLength)
            }
        }

        private fun forwardToUpstream(
            packet: ByteArray,
            length: Int,
            ihl: Int,
            srcPort: Int,
            destPort: Int,
            dnsOffset: Int,
            dnsLength: Int
        ) {
            val dnsPayload = packet.copyOfRange(dnsOffset, dnsOffset + dnsLength)
            var attempts = 0
            while (attempts < upstreamServers.size) {
                val upstream = upstreamServers[currentUpstreamIndex]
                if (DEBUG_DNS) {
                    Log.d(TAG, "Forwarding DNS to upstream ${upstream.address}:${upstream.port}; attempt ${attempts + 1}")
                }
                if (tryUpstream(upstream, dnsPayload, packet, srcPort, destPort)) {
                    return
                }
                currentUpstreamIndex = (currentUpstreamIndex + 1) % upstreamServers.size
                attempts++
            }

            val fallback = tryBuildOriginalDestination(packet, destPort)
            if (fallback != null) {
                if (DEBUG_DNS) {
                    Log.d(TAG, "Trying original DNS destination ${fallback.address}:${fallback.port} after upstream failures")
                }
                if (tryUpstream(fallback, dnsPayload, packet, srcPort, destPort)) {
                    Log.w(TAG, "Used fallback DNS ${fallback.address} after upstream failures")
                    return
                }
            }

            Log.w(TAG, "All upstream DNS servers failed for current request; letting client retry (failOpen=$failOpen)")
            recordUpstreamFailure()
        }

        private fun tryUpstream(
            upstream: InetSocketAddress,
            dnsPayload: ByteArray,
            packet: ByteArray,
            srcPort: Int,
            destPort: Int
        ): Boolean {
            return try {
                val request = DatagramPacket(dnsPayload, dnsPayload.size, upstream)
                socket.send(request)

                val responseBuffer = ByteArray(4096)
                val responsePacket = DatagramPacket(responseBuffer, responseBuffer.size)
                socket.receive(responsePacket)

                recordUpstreamSuccess()

                if (DEBUG_DNS) {
                    Log.d(
                        TAG,
                        "Upstream ${upstream.address} responded len=${responsePacket.length}; sending back to client"
                    )
                }

                val srcIp = packet.copyOfRange(12, 16)
                val destIp = packet.copyOfRange(16, 20)
                val response = buildIpUdpPacket(
                    responsePacket.data,
                    responsePacket.length,
                    destIp,
                    srcIp,
                    destPort,
                    srcPort
                )
                output.write(response, 0, response.size)
                true
            } catch (e: SocketTimeoutException) {
                if (DEBUG_DNS) {
                    Log.d(TAG, "Upstream timeout for ${upstream.address}")
                }
                recordUpstreamFailure()
                false
            } catch (e: IOException) {
                Log.w(TAG, "Failed to forward DNS request to ${upstream.address}", e)
                recordUpstreamFailure()
                false
            } catch (e: Exception) {
                Log.w(TAG, "Failed to forward DNS request", e)
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
                Log.i(TAG, "Upstream DNS healthy again; returning to filtered mode")
            }
        }

        private fun recordUpstreamFailure() {
            val now = System.currentTimeMillis()
            if (failureWindowStartMs == 0L || now - failureWindowStartMs > FAIL_OPEN_WINDOW_MS) {
                failureWindowStartMs = now
                consecutiveFailures = 1
            } else {
                consecutiveFailures += 1
            }

            if (!failOpen && consecutiveFailures >= FAIL_OPEN_THRESHOLD) {
                failOpen = true
                setFailOpenActive(true)
                Log.w(
                    TAG,
                    "Entering fail-open mode after $consecutiveFailures upstream failures; temporarily bypassing blocklist"
                )
            }
        }

        private fun tryBuildOriginalDestination(packet: ByteArray, destPort: Int): InetSocketAddress? {
            return try {
                val destIp = packet.copyOfRange(16, 20)
                val address = java.net.InetAddress.getByAddress(destIp)
                InetSocketAddress(address, destPort)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to build fallback DNS destination", e)
                null
            }
        }

        private fun sendBlockedResponse(
            packet: ByteArray,
            ihl: Int,
            srcPort: Int,
            destPort: Int,
            dnsOffset: Int,
            questionEnd: Int
        ) {
            val questionLength = questionEnd - (dnsOffset + 12)
            if (questionLength < 0) return

            val dnsResponseLength = 12 + questionLength
            val dnsResponse = ByteArray(dnsResponseLength)
            // Copy transaction ID
            System.arraycopy(packet, dnsOffset, dnsResponse, 0, 2)
            val requestFlags = readUint16(packet, dnsOffset + 2)
            var responseFlags = requestFlags or 0x8000 // QR = 1
            responseFlags = (responseFlags and 0xFFF0) or 3 // RCODE = 3 (NXDOMAIN)
            writeUint16(dnsResponse, 2, responseFlags)
            writeUint16(dnsResponse, 4, 1) // QDCOUNT
            writeUint16(dnsResponse, 6, 0) // ANCOUNT
            writeUint16(dnsResponse, 8, 0) // NSCOUNT
            writeUint16(dnsResponse, 10, 0) // ARCOUNT

            // Copy question section
            System.arraycopy(packet, dnsOffset + 12, dnsResponse, 12, questionLength)

            val srcIp = packet.copyOfRange(12, 16)
            val destIp = packet.copyOfRange(16, 20)
            val response = buildIpUdpPacket(dnsResponse, dnsResponse.size, destIp, srcIp, destPort, srcPort)
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

            buffer[0] = 0x45.toByte() // Version + IHL
            buffer[1] = 0
            writeUint16(buffer, 2, totalLength)
            writeUint16(buffer, 4, 0) // Identification
            writeUint16(buffer, 6, 0) // Flags and Fragment Offset
            buffer[8] = 64.toByte() // TTL
            buffer[9] = 17.toByte() // Protocol UDP

            System.arraycopy(srcIp, 0, buffer, 12, 4)
            System.arraycopy(destIp, 0, buffer, 16, 4)
            val checksum = computeIpv4Checksum(buffer, 0, ipHeaderLength)
            writeUint16(buffer, 10, checksum)

            val udpOffset = ipHeaderLength
            writeUint16(buffer, udpOffset, srcPort)
            writeUint16(buffer, udpOffset + 2, destPort)
            writeUint16(buffer, udpOffset + 4, udpHeaderLength + payloadLength)
            writeUint16(buffer, udpOffset + 6, 0) // UDP checksum optional for IPv4

            System.arraycopy(payload, 0, buffer, udpOffset + udpHeaderLength, payloadLength)
            return buffer
        }

        private fun extractQuery(packet: ByteArray, dnsOffset: Int, dnsLength: Int): DnsQuery? {
            if (dnsLength < 12) return null
            val qdCount = readUint16(packet, dnsOffset + 4)
            if (qdCount < 1) return null
            val labels = mutableListOf<String>()
            val end = dnsOffset + dnsLength
            var pos = dnsOffset + 12
            while (pos < end) {
                val lenByte = packet[pos].toInt() and 0xFF
                pos += 1
                if (lenByte == 0) break
                if (pos > end) return null
                if (pos + lenByte > end) return null
                val label = String(packet, pos, lenByte, Charsets.UTF_8)
                labels.add(label)
                pos += lenByte
            }
            if (labels.isEmpty()) return null
            if (pos + 4 > end) return null
            val questionEnd = pos + 4
            val domain = labels.joinToString(".")
            return DnsQuery(domain.lowercase(), questionEnd)
        }

        private fun readUint16(data: ByteArray, offset: Int): Int {
            return ((data[offset].toInt() and 0xFF) shl 8) or (data[offset + 1].toInt() and 0xFF)
        }

        private fun writeUint16(buffer: ByteArray, offset: Int, value: Int) {
            buffer[offset] = (value shr 8).toByte()
            buffer[offset + 1] = (value and 0xFF).toByte()
        }

        private fun computeIpv4Checksum(buffer: ByteArray, offset: Int, length: Int): Int {
            var sum = 0
            var i = offset
            while (i < offset + length) {
                val value = ((buffer[i].toInt() and 0xFF) shl 8) or (buffer[i + 1].toInt() and 0xFF)
                sum += value
                while (sum > 0xFFFF) {
                    sum = (sum and 0xFFFF) + (sum ushr 16)
                }
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
        const val ACTION_APPLY_PROTECTION_MODE = "com.example.digital_defender.APPLY_PROTECTION_MODE"
        private const val FAIL_OPEN_THRESHOLD = 5
        private const val FAIL_OPEN_WINDOW_MS = 15_000L

        fun readBlockedCount(context: Context): Long {
            return DigitalDefenderStats.readBlockedCount(context)
        }
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
        if (now - lastUpdate < BLOCKLIST_REFRESH_INTERVAL_MS) {
            Log.d(TAG, "Skipping blocklist refresh; last attempted at $lastUpdate")
            return
        }

        thread(name = "BlocklistRefresh", start = true) {
            val succeeded = blocklist.refreshFromNetwork(this)
            val timestamp = System.currentTimeMillis()
            preferences.edit().putLong(KEY_LAST_BLOCKLIST_UPDATE, timestamp).apply()
            Log.i(
                TAG,
                if (succeeded) {
                    "Blocklist refreshed for mode ${DomainBlocklist.getProtectionMode(this)} at $timestamp"
                } else {
                    "Blocklist refresh failed at $timestamp; using existing list"
                }
            )
        }
    }
}

data class BlockedEntry(
    val domain: String,
    val timestamp: Long
)

object DigitalDefenderStats {
    private const val MAX_RECENT = 100

    fun readBlockedCount(context: Context): Long {
        return context.getSharedPreferences(DigitalDefenderVpnService.PREFS_NAME, Context.MODE_PRIVATE)
            .getLong(DigitalDefenderVpnService.KEY_BLOCKED_COUNT, 0L)
    }

    fun readSessionBlockedCount(context: Context): Long {
        return context.getSharedPreferences(DigitalDefenderVpnService.PREFS_NAME, Context.MODE_PRIVATE)
            .getLong(DigitalDefenderVpnService.KEY_SESSION_BLOCKED_COUNT, 0L)
    }

    fun readFailOpenActive(context: Context): Boolean {
        return context.getSharedPreferences(DigitalDefenderVpnService.PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(DigitalDefenderVpnService.KEY_FAIL_OPEN_ACTIVE, false)
    }

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
        val updatedCount = prefs.getLong(DigitalDefenderVpnService.KEY_BLOCKED_COUNT, 0L) + 1
        val updatedSession = prefs.getLong(DigitalDefenderVpnService.KEY_SESSION_BLOCKED_COUNT, 0L) + 1
        val recent = loadRecent(prefs).apply {
            add(BlockedEntry(domain, System.currentTimeMillis()))
            if (size > MAX_RECENT) {
                removeAt(0)
            }
        }

        val editor = prefs.edit()
        editor.putLong(DigitalDefenderVpnService.KEY_BLOCKED_COUNT, updatedCount)
        editor.putLong(DigitalDefenderVpnService.KEY_SESSION_BLOCKED_COUNT, updatedSession)
        editor.putString(DigitalDefenderVpnService.KEY_RECENT_BLOCKS, serializeRecent(recent))
        editor.apply()
        return StatsUpdate(updatedCount, updatedSession)
    }

    @Synchronized
    fun getStatsJson(context: Context): String {
        val prefs = context.getSharedPreferences(DigitalDefenderVpnService.PREFS_NAME, Context.MODE_PRIVATE)
        val blockedCount = prefs.getLong(DigitalDefenderVpnService.KEY_BLOCKED_COUNT, 0L)
        val sessionBlocked = prefs.getLong(DigitalDefenderVpnService.KEY_SESSION_BLOCKED_COUNT, 0L)
        val protectionEnabled = prefs.getBoolean(DigitalDefenderVpnService.KEY_PROTECTION_ENABLED, false)
        val protectionMode = DomainBlocklist.getProtectionMode(context)
        val failOpenActive = prefs.getBoolean(DigitalDefenderVpnService.KEY_FAIL_OPEN_ACTIVE, false)
        val recent = loadRecent(prefs)

        val recentArray = JSONArray()
        recent.forEach { entry ->
            val jsonEntry = JSONObject()
            jsonEntry.put("domain", entry.domain)
            jsonEntry.put("timestamp", entry.timestamp)
            recentArray.put(jsonEntry)
        }

        val root = JSONObject()
        root.put("blockedCount", blockedCount)
        root.put("sessionBlocked", sessionBlocked)
        root.put("running", protectionEnabled)
        root.put("mode", protectionMode)
        root.put("failOpenActive", failOpenActive)
        root.put("recent", recentArray)
        return root.toString()
    }

    @Synchronized
    fun resetStats(context: Context) {
        val prefs = context.getSharedPreferences(DigitalDefenderVpnService.PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putLong(DigitalDefenderVpnService.KEY_BLOCKED_COUNT, 0L)
            .putLong(DigitalDefenderVpnService.KEY_SESSION_BLOCKED_COUNT, 0L)
            .putString(DigitalDefenderVpnService.KEY_RECENT_BLOCKS, JSONArray().toString())
            .apply()
    }

    @Synchronized
    fun clearRecent(context: Context) {
        val prefs = context.getSharedPreferences(DigitalDefenderVpnService.PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putString(DigitalDefenderVpnService.KEY_RECENT_BLOCKS, JSONArray().toString())
            .apply()
    }

    private fun loadRecent(prefs: SharedPreferences): MutableList<BlockedEntry> {
        val recentRaw = prefs.getString(DigitalDefenderVpnService.KEY_RECENT_BLOCKS, "")
        if (recentRaw.isNullOrBlank()) return mutableListOf()

        return try {
            val array = JSONArray(recentRaw)
            MutableList(array.length()) { index ->
                val obj = array.getJSONObject(index)
                BlockedEntry(
                    domain = obj.optString("domain", ""),
                    timestamp = obj.optLong("timestamp", 0L)
                )
            }.filter { it.domain.isNotBlank() }.toMutableList()
        } catch (e: Exception) {
            Log.w(DigitalDefenderVpnService.TAG, "Failed to parse recent blocks", e)
            mutableListOf()
        }
    }

    private fun serializeRecent(entries: List<BlockedEntry>): String {
        val array = JSONArray()
        entries.forEach { entry ->
            val obj = JSONObject()
            obj.put("domain", entry.domain)
            obj.put("timestamp", entry.timestamp)
            array.put(obj)
        }
        return array.toString()
    }
}
