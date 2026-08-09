package com.horizon.horizonptz.camera

/**
 * Configuration for the AVer PTZ Camera.
 */
data class CameraConfig(
    val ipAddress: String,
    val controlPort: Int = 52381,
    val rtspUrl: String,
    val account: String,
    val password: String,
    val camName: String = "Camera",
    val rtspPort: Int = 554,
    val useTcp: Boolean = true,
    val protocol: String = "VISCA/UDP",
    val rtspPath: String = "/live_st1",
    val showPort: Boolean = false,
    val autoConnect: Boolean = true,
    val engine: String = "Media3"
)
