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
    private var running = false
    private val blocklist = DomainBlocklist
    private lateinit var preferences: SharedPreferences
    private var blockedCount: Long = 0
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
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand: starting foreground with type specialUse")
        return try {
            createNotificationChannel()
            startForeground(NOTIFICATION_ID, buildNotification())
            startProtection()
            START_STICKY
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start VPN service", e)
            stopProtection()
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
                stopSelf()
            } else {
                Log.d(TAG, "VPN interface established")
                startWorker(vpnInterface!!)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error starting VPN", e)
            stopProtection()
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
        Log.d(TAG, "Stopping protection")
        running = false
        try {
            worker?.stop()
            workerThread?.interrupt()
            workerThread?.join(500)
            workerThread = null
            vpnInterface?.close()
        } catch (e: Exception) {
            Log.w(TAG, "Error closing VPN interface", e)
        } finally {
            worker = null
            vpnInterface = null
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
            vpnService.protect(this)
        }

        fun run() {
            val buffer = ByteArray(32767)
            try {
                while (active && running) {
                    try {
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

            val udpOffset = ihl
            val srcPort = readUint16(packet, udpOffset)
            val destPort = readUint16(packet, udpOffset + 2)
            if (destPort != 53) return

            val udpLength = readUint16(packet, udpOffset + 4)
            if (udpLength < 8) return
            if (udpOffset + udpLength > length) return

            val dnsOffset = udpOffset + 8
            val dnsLength = length - dnsOffset
            if (dnsLength <= 0) return
            if (dnsLength > 1500) {
                forwardToUpstream(packet, length, ihl, srcPort, destPort, dnsOffset, dnsLength)
                return
            }

            val query = extractQuery(packet, dnsOffset, dnsLength)
            if (query == null) {
                if (DEBUG_DNS) {
                    Log.d(TAG, "DNS query: <parse_error> -> PARSE_ERROR")
                }
                forwardToUpstream(packet, length, ihl, srcPort, destPort, dnsOffset, dnsLength)
                return
            }

            val domain = query.domain
            if (blocklist.isBlocked(domain)) {
                if (DEBUG_DNS) {
                    Log.d(TAG, "DNS query: $domain -> BLOCKED")
                }
                incrementBlockedCount()
                sendBlockedResponse(packet, ihl, srcPort, destPort, dnsOffset, query.questionEnd)
            } else {
                if (DEBUG_DNS) {
                    Log.d(TAG, "DNS query: $domain -> ALLOWED")
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
            var attempts = 0
            while (attempts < upstreamServers.size) {
                val upstream = upstreamServers[currentUpstreamIndex]
                try {
                    val dnsPayload = packet.copyOfRange(dnsOffset, dnsOffset + dnsLength)
                    val request = DatagramPacket(dnsPayload, dnsPayload.size, upstream)
                    socket.send(request)

                    val responseBuffer = ByteArray(512)
                    val responsePacket = DatagramPacket(responseBuffer, responseBuffer.size)
                    socket.receive(responsePacket)

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
                    return
                } catch (e: SocketTimeoutException) {
                    if (DEBUG_DNS) {
                        Log.d(TAG, "Upstream timeout for ${upstream.address}")
                    }
                } catch (e: IOException) {
                    Log.w(TAG, "Failed to forward DNS request to ${upstream.address}", e)
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to forward DNS request", e)
                    return
                }
                currentUpstreamIndex = (currentUpstreamIndex + 1) % upstreamServers.size
                attempts++
            }
            Log.w(TAG, "All upstream DNS servers failed for current request")
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
        private const val TAG = "DigitalDefenderVpnService"
        private const val DEBUG_DNS = false
        private const val PREFS_NAME = "digital_defender_prefs"
        private const val KEY_BLOCKED_COUNT = "blocked_count"
        private const val KEY_LAST_BLOCKLIST_UPDATE = "last_blocklist_update"
        private const val BLOCKLIST_URL = "https://example.com/digital-defender/blocklist.txt" // TODO: replace with real URL
        private const val BLOCKLIST_REFRESH_INTERVAL_MS = 60 * 60 * 1000L

        fun readBlockedCount(context: Context): Long {
            return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getLong(KEY_BLOCKED_COUNT, 0L)
        }
    }

    @Synchronized
    private fun incrementBlockedCount() {
        blockedCount += 1
        preferences.edit().putLong(KEY_BLOCKED_COUNT, blockedCount).apply()
    }

    private fun maybeRefreshBlocklist() {
        val now = System.currentTimeMillis()
        val lastUpdate = preferences.getLong(KEY_LAST_BLOCKLIST_UPDATE, 0L)
        if (now - lastUpdate < BLOCKLIST_REFRESH_INTERVAL_MS) {
            Log.d(TAG, "Skipping blocklist refresh; last attempted at $lastUpdate")
            return
        }

        thread(name = "BlocklistRefresh", start = true) {
            blocklist.refreshFromNetwork(this, BLOCKLIST_URL)
            preferences.edit().putLong(KEY_LAST_BLOCKLIST_UPDATE, System.currentTimeMillis()).apply()
        }
    }
}
