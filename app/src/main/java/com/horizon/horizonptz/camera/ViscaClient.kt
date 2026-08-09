package com.horizon.horizonptz.camera

import android.util.Log
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/**
 * VISCA over IP client for controlling PTZ cameras via UDP.
 */
class ViscaClient(private val config: CameraConfig) {
    private val sequenceNumber = AtomicInteger(0)
    private val executor = Executors.newSingleThreadExecutor()

    companion object {
        private const val TAG = "ViscaClient"
        private const val HEADER_SIZE = 8
        private val PAYLOAD_TYPE_COMMAND = byteArrayOf(0x01, 0x00)
        private val PAYLOAD_TYPE_INQUIRY = byteArrayOf(0x01, 0x10)
    }

    /**
     * Sends a VISCA command to the camera.
     * @param payload The VISCA message payload (without header).
     * @param isInquiry True if this is an inquiry (01 10), false for a command (01 00).
     */
    fun sendCommand(payload: ByteArray, isInquiry: Boolean = false) {
        val seq = sequenceNumber.getAndIncrement()
        val packetData = buildPacket(payload, isInquiry, seq)

        executor.execute {
            try {
                DatagramSocket().use { socket ->
                    val address = InetAddress.getByName(config.ipAddress)
                    val packet = DatagramPacket(
                        packetData,
                        packetData.size,
                        address,
                        config.controlPort
                    )
                    socket.send(packet)
                    Log.d(TAG, "Sent VISCA ${if (isInquiry) "Inquiry" else "Command"}: ${packetData.joinToString(" ") { "%02X".format(it) }}")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error sending VISCA packet", e)
            }
        }
    }

    /**
     * Helper to build the 8-byte header + payload.
     */
    fun buildPacket(payload: ByteArray, isInquiry: Boolean, seq: Int): ByteArray {
        val packet = ByteArray(HEADER_SIZE + payload.size)
        
        // Byte 0-1: Payload Type
        val type = if (isInquiry) PAYLOAD_TYPE_INQUIRY else PAYLOAD_TYPE_COMMAND
        packet[0] = type[0]
        packet[1] = type[1]

        // Byte 2-3: Payload Length
        packet[2] = ((payload.size shr 8) and 0xFF).toByte()
        packet[3] = (payload.size and 0xFF).toByte()

        // Byte 4-7: Sequence Number
        packet[4] = ((seq shr 24) and 0xFF).toByte()
        packet[5] = ((seq shr 16) and 0xFF).toByte()
        packet[6] = ((seq shr 8) and 0xFF).toByte()
        packet[7] = (seq and 0xFF).toByte()

        // Payload
        System.arraycopy(payload, 0, packet, HEADER_SIZE, payload.size)
        
        return packet
    }

    /**
     * 發送 PTZ 控制指令 (8x 01 06 01 VV WW 03 01 FF)
     * @param panSpeed 水平速度 (0x01-0x18)
     * @param tiltSpeed 垂直速度 (0x01-0x14)
     * @param panMode 0: 停止, 1: 左, 2: 右
     * @param tiltMode 0: 停止, 1: 上, 2: 下
     */
    fun sendPtzCommand(panSpeed: Int, tiltSpeed: Int, panMode: Int, tiltMode: Int) {
        val payload = ByteArray(9)
        payload[0] = 0x81.toByte()
        payload[1] = 0x01
        payload[2] = 0x06
        payload[3] = 0x01
        payload[4] = (panSpeed and 0xFF).toByte()
        payload[5] = (tiltSpeed and 0xFF).toByte()
        
        // Byte 6: Pan (01: Left, 02: Right, 03: Stop)
        payload[6] = when (panMode) {
            1 -> 0x01
            2 -> 0x02
            else -> 0x03
        }
        
        // Byte 7: Tilt (01: Up, 02: Down, 03: Stop)
        payload[7] = when (tiltMode) {
            1 -> 0x01
            2 -> 0x02
            else -> 0x03
        }
        
        payload[8] = 0xFF.toByte()
        sendCommand(payload)
    }

    /**
     * 發送縮放指令 (8x 01 04 07 2p/3p/00 FF)
     * @param mode 0: 停止, 1: 放大 (Tele), 2: 縮小 (Wide)
     * @param speed 速度 (0-7)
     */
    fun sendZoomCommand(mode: Int, speed: Int) {
        val payload = ByteArray(6)
        payload[0] = 0x81.toByte()
        payload[1] = 0x01
        payload[2] = 0x04
        payload[3] = 0x07
        
        payload[4] = when (mode) {
            1 -> (0x20 or (speed and 0x07)).toByte() // Tele
            2 -> (0x30 or (speed and 0x07)).toByte() // Wide
            else -> 0x00 // Stop
        }
        
        payload[5] = 0xFF.toByte()
        sendCommand(payload)
    }

    /**
     * 發送預設位指令 (Call: 8x 01 04 3F 02 pp FF, Set: 8x 01 04 3F 01 pp FF)
     * @param mode 1: 設定 (Set), 2: 呼叫 (Recall)
     * @param presetIndex 預設位編號 (1-127)
     */
    fun sendPresetCommand(mode: Int, presetIndex: Int) {
        val payload = byteArrayOf(
            0x81.toByte(), 0x01, 0x04, 0x3F, 
            mode.toByte(), 
            presetIndex.toByte(), 
            0xFF.toByte()
        )
        sendCommand(payload)
    }

    /**
     * 測試連線：發送電源查詢指令 (8x 09 04 00 FF)
     * 由於 UDP 是無狀態的，此處實作簡易的超時監聽
     */
    fun testConnection(callback: (Boolean) -> Unit) {
        val payload = byteArrayOf(0x81.toByte(), 0x09, 0x04, 0x00, 0xFF.toByte())
        val seq = sequenceNumber.getAndIncrement()
        val packetData = buildPacket(payload, isInquiry = true, seq = seq)

        executor.execute {
            try {
                DatagramSocket().use { socket ->
                    socket.soTimeout = 2000 // 2秒超時
                    val address = InetAddress.getByName(config.ipAddress)
                    val packet = DatagramPacket(packetData, packetData.size, address, config.controlPort)
                    socket.send(packet)

                    val buffer = ByteArray(1024)
                    val response = DatagramPacket(buffer, buffer.size)
                    socket.receive(response)
                    
                    // 只要有收到任何回應，代表連線成功
                    Log.d(TAG, "Received test response from ${config.ipAddress}")
                    callback(true)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Connection test failed for ${config.ipAddress}", e)
                callback(false)
            }
        }
    }

    /**
     * Utility to convert Hex string to ByteArray.
     */
    fun hexToBytes(hex: String): ByteArray {
        val cleanHex = hex.replace(" ", "")
        val len = cleanHex.length
        val data = ByteArray(len / 2)
        var i = 0
        while (i < len) {
            data[i / 2] = ((Character.digit(cleanHex[i], 16) shl 4) +
                    Character.digit(cleanHex[i + 1], 16)).toByte()
            i += 2
        }
        return data
    }
}
