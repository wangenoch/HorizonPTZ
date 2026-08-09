package com.horizon.horizonptz.config

/**
 * 全局配置管理中心 (Single Source of Truth)
 */
object AppConfig {
    const val APP_NAME = "HorizonPTZ"
    const val APP_VERSION = "V0.5"

    // 預設連線參數
    const val DEFAULT_VISCA_PORT = 52381
    const val DEFAULT_RTSP_PORT = 554
    const val DEFAULT_PROTOCOL = "VISCA/UDP"
    const val DEFAULT_EXPO_STRENGTH = 2.0f
    
    // 預設憑證
    const val DEFAULT_ACCOUNT = "admin"
    const val DEFAULT_PASSWORD = "admin"

    // 預設 IP
    const val DEFAULT_IP_CAM1 = "192.168.5.153"
    const val DEFAULT_IP_CAM2 = "192.168.5.163"

    // 預設 RTSP 路徑
    const val DEFAULT_RTSP_PATH = "/live/av1"

    // 逾時設定
    const val CONNECTION_TEST_TIMEOUT = 2000
    const val WATCHDOG_RECONNECT_DELAY = 5000L

    // 指令定義
    object Visca {
        val PAYLOAD_TYPE_COMMAND = byteArrayOf(0x01, 0x00)
        val PAYLOAD_TYPE_INQUIRY = byteArrayOf(0x01, 0x10)
        const val HEADER_SIZE = 8
    }
}
