package com.example.digital_defender

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat
import io.flutter.FlutterInjector
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import java.io.ByteArrayOutputStream
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.nio.ByteBuffer
import java.util.Locale

class DigitalDefenderVpnService : VpnService() {
    private var vpnInterface: ParcelFileDescriptor? = null
    private var serviceJob: Job? = null
    private val blocklist = mutableSetOf<String>()

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createNotificationChannel()
        startForeground(1, buildNotification())
        loadBlocklist()
        startProtection()
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        stopProtection()
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
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.vpn_channel_name))
            .setContentText(getString(R.string.vpn_channel_description))
            .setSmallIcon(android.R.drawable.stat_sys_warning)
            .setOngoing(true)
        return builder.build()
    }

    private fun loadBlocklist() {
        try {
            val loader = FlutterInjector.instance().flutterLoader()
            val key = loader.getLookupKeyForAsset("assets/blocklists/android_basic.txt")
            assets.open(key).bufferedReader().useLines { lines ->
                lines.map { it.trim().lowercase(Locale.US) }
                    .filter { it.isNotEmpty() && !it.startsWith("#") }
                    .forEach { blocklist.add(it) }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun startProtection() {
        stopProtection()
        val builder = Builder()
        builder.setSession("Digital Defender")
            .setBlocking(true)
            .addAddress("10.0.0.2", 32)
            .addDnsServer("1.1.1.1")
            .addDnsServer("8.8.8.8")
            .addRoute("0.0.0.0", 0)
        vpnInterface = builder.establish()

        serviceJob = CoroutineScope(Dispatchers.IO).launch {
            vpnInterface?.let { tun ->
                handleTraffic(tun)
            }
        }
    }

    private fun stopProtection() {
        serviceJob?.cancel()
        serviceJob = null
        vpnInterface?.close()
        vpnInterface = null
    }

    private fun handleTraffic(tunInterface: ParcelFileDescriptor) {
        val input = FileInputStream(tunInterface.fileDescriptor)
        val output = FileOutputStream(tunInterface.fileDescriptor)
        val packet = ByteArray(4096)
        val dnsSocket = DatagramSocket(null).apply {
            reuseAddress = true
            bind(InetSocketAddress(0))
            protect(this)
        }
        val upstream = InetSocketAddress(InetAddress.getByName("1.1.1.1"), 53)

        while (!Thread.interrupted()) {
            val length = input.read(packet)
            if (length <= 0) continue
            val buffer = ByteBuffer.wrap(packet, 0, length)
            val protocol = buffer.get(9).toInt() and 0xFF
            // 17 = UDP
            if (protocol == 17) {
                val sourcePort = buffer.getShort(20).toInt() and 0xFFFF
                val destPort = buffer.getShort(22).toInt() and 0xFFFF
                if (destPort == 53) {
                    val dnsDataOffset = ((buffer.get(0).toInt() and 0x0F) * 4) + 8 + 12
                    val dnsPayload = packet.copyOfRange(dnsDataOffset, length)
                    val domain = parseDomain(dnsPayload)
                    if (domain != null && blocklist.contains(domain.lowercase(Locale.US))) {
                        val response = buildBlockedResponse(dnsPayload)
                        val sendBuffer = packet.copyOf()
                        System.arraycopy(response, 0, sendBuffer, dnsDataOffset, response.size)
                        output.write(sendBuffer, 0, dnsDataOffset + response.size)
                        continue
                    }
                    val requestPacket = DatagramPacket(dnsPayload, dnsPayload.size, upstream)
                    dnsSocket.send(requestPacket)
                    val reply = DatagramPacket(ByteArray(1500), 1500)
                    dnsSocket.receive(reply)
                    val response = reply.data.copyOf(reply.length)
                    val sendBuffer = packet.copyOf()
                    System.arraycopy(response, 0, sendBuffer, dnsDataOffset, response.size)
                    output.write(sendBuffer, 0, dnsDataOffset + response.size)
                } else {
                    // Non-DNS traffic simply dropped in this MVP.
                }
            }
        }
    }

    private fun parseDomain(data: ByteArray): String? {
        return try {
            var position = 12
            val labels = mutableListOf<String>()
            while (position < data.size) {
                val len = data[position].toInt()
                if (len == 0) break
                position += 1
                if (position + len > data.size) break
                labels.add(String(data, position, len))
                position += len
            }
            labels.joinToString(".")
        } catch (e: Exception) {
            null
        }
    }

    private fun buildBlockedResponse(request: ByteArray): ByteArray {
        val baos = ByteArrayOutputStream()
        val buffer = ByteBuffer.wrap(request)
        val transactionId = ByteArray(2)
        buffer.get(transactionId)
        baos.write(transactionId)
        baos.write(byteArrayOf(0x81.toByte(), 0x83.toByte())) // QR + NXDOMAIN
        baos.write(request, 4, request.size - 4)
        return baos.toByteArray()
    }

    companion object {
        private const val CHANNEL_ID = "digital_defender_vpn"
    }
}
