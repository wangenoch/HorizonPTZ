package com.horizon.horizonptz

import com.horizon.horizonptz.camera.CameraConfig
import com.horizon.horizonptz.camera.ViscaClient
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class ViscaClientTest {

    private val config = CameraConfig(
        ipAddress = "192.168.1.100",
        rtspUrl = "rtsp://192.168.1.100/live",
        account = "admin",
        password = "password"
    )
    private val client = ViscaClient(config)

    @Test
    fun testBuildPacketCommand() {
        val payload = byteArrayOf(0x81.toByte(), 0x01, 0x04, 0x00, 0x02, 0xFF.toByte())
        val seq = 1
        val packet = client.buildPacket(payload, isInquiry = false, seq = seq)

        // Expected Header:
        // Byte 0-1: 01 00 (Command)
        // Byte 2-3: 00 06 (Length)
        // Byte 4-7: 00 00 00 01 (Sequence)
        val expectedHeader = byteArrayOf(
            0x01, 0x00,
            0x00, 0x06,
            0x00, 0x00, 0x00, 0x01
        )
        
        val actualHeader = packet.copyOfRange(0, 8)
        assertArrayEquals("Header mismatch", expectedHeader, actualHeader)
        
        val actualPayload = packet.copyOfRange(8, packet.size)
        assertArrayEquals("Payload mismatch", payload, actualPayload)
    }

    @Test
    fun testBuildPacketInquiry() {
        val payload = byteArrayOf(0x81.toByte(), 0x09, 0x04, 0x00, 0xFF.toByte())
        val seq = 0x12345678
        val packet = client.buildPacket(payload, isInquiry = true, seq = seq)

        // Expected Header:
        // Byte 0-1: 01 10 (Inquiry)
        // Byte 2-3: 00 05 (Length)
        // Byte 4-7: 12 34 56 78 (Sequence)
        val expectedHeader = byteArrayOf(
            0x01, 0x10,
            0x00, 0x05,
            0x12, 0x34, 0x56, 0x78.toByte()
        )
        
        val actualHeader = packet.copyOfRange(0, 8)
        assertArrayEquals("Header mismatch for inquiry", expectedHeader, actualHeader)
    }

    @Test
    fun testHexToBytes() {
        val hex = "81 01 04 00 02 FF"
        val expected = byteArrayOf(0x81.toByte(), 0x01, 0x04, 0x00, 0x02, 0xFF.toByte())
        assertArrayEquals(expected, client.hexToBytes(hex))
    }

    @Test
    fun testBuildPtzPacket() {
        // Pan Right (02), Tilt Up (01), Max Speeds
        val payload = byteArrayOf(
            0x81.toByte(), 0x01, 0x06, 0x01, 
            0x18.toByte(), 0x14.toByte(), 
            0x02, 0x01, 0xFF.toByte()
        )
        val packet = client.buildPacket(payload, isInquiry = false, seq = 1)
        
        val expectedHeader = byteArrayOf(
            0x01, 0x00,
            0x00, 0x09,
            0x00, 0x00, 0x00, 0x01
        )
        assertArrayEquals(expectedHeader, packet.copyOfRange(0, 8))
        assertArrayEquals(payload, packet.copyOfRange(8, packet.size))
    }

    @Test
    fun testBuildZoomPacket() {
        // Zoom In (Tele: 2x), Speed 7
        val payload = byteArrayOf(
            0x81.toByte(), 0x01, 0x04, 0x07, 
            0x27.toByte(), 0xFF.toByte()
        )
        val packet = client.buildPacket(payload, isInquiry = false, seq = 2)
        
        val expectedHeader = byteArrayOf(
            0x01, 0x00,
            0x00, 0x06,
            0x00, 0x00, 0x00, 0x02
        )
        assertArrayEquals(expectedHeader, packet.copyOfRange(0, 8))
        assertArrayEquals(payload, packet.copyOfRange(8, packet.size))
    }
}
