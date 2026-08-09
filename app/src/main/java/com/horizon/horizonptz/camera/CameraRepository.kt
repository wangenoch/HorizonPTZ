package com.horizon.horizonptz.camera

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKeys
import com.horizon.horizonptz.config.AppConfig

class CameraRepository(context: Context) {

    private val masterKeyAlias = MasterKeys.getOrCreate(MasterKeys.AES256_GCM_SPEC)

    private val sharedPreferences = EncryptedSharedPreferences.create(
        "camera_prefs",
        masterKeyAlias,
        context,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )

    fun saveConfig(index: Int, config: CameraConfig) {
        sharedPreferences.edit().apply {
            putString("cam_${index}_name", config.camName)
            putString("cam_${index}_ip", config.ipAddress)
            putInt("cam_${index}_port", config.controlPort)
            putInt("cam_${index}_rtsp_port", config.rtspPort)
            putString("cam_${index}_rtsp_path", config.rtspPath)
            putString("cam_${index}_account", config.account)
            putString("cam_${index}_password", config.password)
            putBoolean("cam_${index}_use_tcp", config.useTcp)
            putString("cam_${index}_protocol", config.protocol)
            putBoolean("cam_${index}_show_port", config.showPort)
            putBoolean("cam_${index}_auto_connect", config.autoConnect)
            putString("cam_${index}_engine", config.engine)
            apply()
        }
    }

    fun getConfig(index: Int): CameraConfig {
        val defaultIp = if (index == 1) AppConfig.DEFAULT_IP_CAM1 else AppConfig.DEFAULT_IP_CAM2
        
        val name = sharedPreferences.getString("cam_${index}_name", "CAM 0$index") ?: "CAM 0$index"
        val ip = sharedPreferences.getString("cam_${index}_ip", defaultIp) ?: defaultIp
        val port = sharedPreferences.getInt("cam_${index}_port", AppConfig.DEFAULT_VISCA_PORT)
        val rtspPort = sharedPreferences.getInt("cam_${index}_rtsp_port", AppConfig.DEFAULT_RTSP_PORT)
        val rtspPath = sharedPreferences.getString("cam_${index}_rtsp_path", AppConfig.DEFAULT_RTSP_PATH) ?: AppConfig.DEFAULT_RTSP_PATH
        val account = sharedPreferences.getString("cam_${index}_account", AppConfig.DEFAULT_ACCOUNT) ?: AppConfig.DEFAULT_ACCOUNT
        val password = sharedPreferences.getString("cam_${index}_password", AppConfig.DEFAULT_PASSWORD) ?: AppConfig.DEFAULT_PASSWORD
        val useTcp = sharedPreferences.getBoolean("cam_${index}_use_tcp", true)
        val protocol = sharedPreferences.getString("cam_${index}_protocol", AppConfig.DEFAULT_PROTOCOL) ?: AppConfig.DEFAULT_PROTOCOL
        val showPort = sharedPreferences.getBoolean("cam_${index}_show_port", false)
        val autoConnect = sharedPreferences.getBoolean("cam_${index}_auto_connect", true)
        val engine = sharedPreferences.getString("cam_${index}_engine", "Media3") ?: "Media3"
        
        val portSuffix = if (showPort) ":$rtspPort" else ""
        
        // 組合完整的帶認證 RTSP URL
        val rtspUrl = "rtsp://$account:$password@$ip$portSuffix${if (rtspPath.startsWith("/")) "" else "/"}$rtspPath"
        
        return CameraConfig(ip, port, rtspUrl, account, password, name, rtspPort, useTcp, protocol, rtspPath, showPort, autoConnect, engine)
    }

    fun isVirtualJoystickEnabled(): Boolean {
        return sharedPreferences.getBoolean("virtual_joystick_enabled", true)
    }

    fun setVirtualJoystickEnabled(enabled: Boolean) {
        sharedPreferences.edit().putBoolean("virtual_joystick_enabled", enabled).apply()
    }

    fun getKeyCode(action: String, default: Int): Int {
        return sharedPreferences.getInt("key_$action", default)
    }

    fun setKeyCode(action: String, keyCode: Int) {
        sharedPreferences.edit().putInt("key_$action", keyCode).apply()
    }

    fun getExpoStrength(): Float {
        return sharedPreferences.getFloat("expo_strength", AppConfig.DEFAULT_EXPO_STRENGTH)
    }

    fun setExpoStrength(strength: Float) {
        sharedPreferences.edit().putFloat("expo_strength", strength).apply()
    }

    fun isShowPortEnabled(): Boolean {
        return sharedPreferences.getBoolean("show_port_enabled", false)
    }

    fun setShowPortEnabled(enabled: Boolean) {
        sharedPreferences.edit().putBoolean("show_port_enabled", enabled).apply()
    }

    // --- Axis Mapping ---
    fun getAxisMapping(action: String, defaultAxis: Int): Int {
        return sharedPreferences.getInt("axis_$action", defaultAxis)
    }

    fun isAxisInverted(action: String): Boolean {
        return sharedPreferences.getBoolean("inverted_$action", false)
    }

    fun saveAxisMapping(action: String, axisId: Int, inverted: Boolean) {
        sharedPreferences.edit().apply {
            putInt("axis_$action", axisId)
            putBoolean("inverted_$action", inverted)
            apply()
        }
    }
}
