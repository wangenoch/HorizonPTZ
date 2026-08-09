package com.horizon.horizonptz

import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.GestureDetector
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.TextView
import android.util.Log
import androidx.annotation.OptIn
import androidx.appcompat.app.AppCompatActivity
import androidx.media3.common.util.UnstableApi
import com.horizon.horizonptz.camera.CameraConfig
import com.horizon.horizonptz.camera.CameraRepository
import com.horizon.horizonptz.camera.UsbJoystickManager
import com.horizon.horizonptz.camera.ViscaClient
import com.horizon.horizonptz.config.AppConfig
import com.horizon.horizonptz.player.PTZPlayer
import com.horizon.horizonptz.player.Media3PlayerWrapper
import com.horizon.horizonptz.player.IjkPlayerWrapper
import com.horizon.horizonptz.ui.VirtualJoystickView
import kotlin.math.abs
import kotlin.math.pow
import kotlin.math.sign

class MainActivity : AppCompatActivity() {

    private val TAG = "MainActivity"
    private var ptzPlayer1: PTZPlayer? = null
    private var ptzPlayer2: PTZPlayer? = null
    
    private val reconnectHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private val RECONNECT_DELAY = 10000L

    private var viscaClient1: ViscaClient? = null
    private var viscaClient2: ViscaClient? = null

    private val watchdogHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private var lastBytes1 = 0L
    private var lastBytes2 = 0L
    
    private lateinit var repository: CameraRepository
    private lateinit var usbJoystickManager: UsbJoystickManager

    private lateinit var containerCam1: FrameLayout
    private lateinit var containerCam2: FrameLayout
    private lateinit var videoContainerCam1: FrameLayout
    private lateinit var videoContainerCam2: FrameLayout
    
    private lateinit var joystickCam1: VirtualJoystickView
    private lateinit var joystickCam2: VirtualJoystickView

    private lateinit var tvStatusCam1: TextView
    private lateinit var tvStatusCam2: TextView
    private lateinit var tvNameCam1: TextView
    private lateinit var tvNameCam2: TextView
    private lateinit var tvProtocolCam1: TextView
    private lateinit var tvProtocolCam2: TextView
    private lateinit var tvStreamCam1: TextView
    private lateinit var tvStreamCam2: TextView
    
    private lateinit var tvDataCam1: TextView
    private lateinit var tvDataCam2: TextView
    
    private lateinit var bgBlueCam1: View
    private lateinit var bgBlueCam2: View

    private var isCam1FullScreen = false
    private var isCam2FullScreen = false

    private var lastPan1 = 0
    private var lastTilt1 = 0
    private var lastPan2 = 0
    private var lastTilt2 = 0
    private var lastZoom = 0

    private var keyC1P1 = KeyEvent.KEYCODE_BUTTON_A
    private var keyC1P2 = KeyEvent.KEYCODE_BUTTON_B
    private var keyC2P1 = KeyEvent.KEYCODE_BUTTON_X
    private var keyC2P2 = KeyEvent.KEYCODE_BUTTON_Y
    private var expoStrength = 2.0f

    private var currentConfig1: CameraConfig? = null
    private var currentConfig2: CameraConfig? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        hideSystemUI()

        repository = (application as HorizonPTZApp).repository
        
        containerCam1 = findViewById(R.id.containerCam1)
        containerCam2 = findViewById(R.id.containerCam2)
        videoContainerCam1 = findViewById(R.id.videoContainerCam1)
        videoContainerCam2 = findViewById(R.id.videoContainerCam2)
        
        joystickCam1 = findViewById(R.id.joystickCam1)
        joystickCam2 = findViewById(R.id.joystickCam2)

        tvStatusCam1 = findViewById(R.id.tvStatusCam1)
        tvStatusCam2 = findViewById(R.id.tvStatusCam2)
        tvNameCam1 = findViewById(R.id.tvNameCam1)
        tvNameCam2 = findViewById(R.id.tvNameCam2)
        tvProtocolCam1 = findViewById(R.id.tvProtocolCam1)
        tvProtocolCam2 = findViewById(R.id.tvProtocolCam2)
        tvStreamCam1 = findViewById(R.id.tvStreamCam1)
        tvStreamCam2 = findViewById(R.id.tvStreamCam2)
        tvDataCam1 = findViewById(R.id.tvDataCam1)
        tvDataCam2 = findViewById(R.id.tvDataCam2)
        
        tvStatusCam1.setOnClickListener { toggleCameraConnection(1) }
        tvStatusCam2.setOnClickListener { toggleCameraConnection(2) }
        
        bgBlueCam1 = findViewById(R.id.bgBlueCam1)
        bgBlueCam2 = findViewById(R.id.bgBlueCam2)

        usbJoystickManager = UsbJoystickManager(this) { device ->
            showModeHint("USB Joystick Ready: ${device.deviceName}")
        }

        findViewById<ImageButton>(R.id.btnSettings).setOnClickListener {
            startActivity(Intent(this, SettingsActivity::class.java))
        }

        setupGestures()
        setupVirtualJoysticks()
        setupPresetButtons()
    }

    private fun hideSystemUI() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
            window.insetsController?.let {
                it.hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
                it.systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (View.SYSTEM_UI_FLAG_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION)
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideSystemUI()
    }

    override fun onStart() {
        super.onStart()
        usbJoystickManager.register()
    }

    override fun onResume() {
        super.onResume()
        loadControlSettings()
        loadCameraConfigs()
        updateJoystickVisibility()
        startDataWatchdog()
    }

    private fun startDataWatchdog() {
        watchdogHandler.removeCallbacksAndMessages(null)
        watchdogHandler.postDelayed(object : Runnable {
            override fun run() {
                checkStreamHealth()
                watchdogHandler.postDelayed(this, 5000)
            }
        }, 5000)
    }

    private fun checkStreamHealth() {
        // 檢查 Player 1
        ptzPlayer1?.let { p ->
            val buffered = p.getBufferedPosition()
            val current = p.getCurrentPosition()
            val latency = (buffered - current).coerceAtLeast(0)
            
            // 修正數據顯示
            val stats = if (p is Media3PlayerWrapper) p.getVideoStats() else "N/A"
            tvDataCam1.text = "SYNC: ${latency}ms | $stats"

            if (p is Media3PlayerWrapper) {
                if (latency > 1500) p.setPlaybackSpeed(1.2f) // 落後 1.5 秒才加速
                else p.setPlaybackSpeed(1.0f)
            }

            if (p.isPlaying() && latency < 10) {
                Log.w(TAG, "Cam 1 buffer low!")
            }
        }

        ptzPlayer2?.let { p ->
            val buffered = p.getBufferedPosition()
            val current = p.getCurrentPosition()
            val latency = (buffered - current).coerceAtLeast(0)
            
            val stats = if (p is Media3PlayerWrapper) p.getVideoStats() else "N/A"
            tvDataCam2.text = "SYNC: ${latency}ms | $stats"
            
            if (p is Media3PlayerWrapper) {
                if (latency > 1500) p.setPlaybackSpeed(1.2f)
                else p.setPlaybackSpeed(1.0f)
            }
        }
    }

    private fun loadControlSettings() {
        keyC1P1 = repository.getKeyCode("C1P1", KeyEvent.KEYCODE_BUTTON_A)
        keyC1P2 = repository.getKeyCode("C1P2", KeyEvent.KEYCODE_BUTTON_B)
        keyC2P1 = repository.getKeyCode("C2P1", KeyEvent.KEYCODE_BUTTON_X)
        keyC2P2 = repository.getKeyCode("C2P2", KeyEvent.KEYCODE_BUTTON_Y)
        expoStrength = repository.getExpoStrength()
    }

    private fun loadCameraConfigs(forceRefresh: Boolean = false) {
        val config1 = repository.getConfig(1)
        val config2 = repository.getConfig(2)

        val configChanged1 = forceRefresh || config1 != currentConfig1
        val configChanged2 = forceRefresh || config2 != currentConfig2

        if (configChanged1) {
            currentConfig1 = config1
            viscaClient1 = ViscaClient(config1)
            tvNameCam1.text = config1.camName
            tvProtocolCam1.text = if (config1.showPort) "CTRL: ${config1.protocol}:${config1.controlPort}" else "CTRL: ${config1.protocol}"
            tvStreamCam1.text = if (config1.showPort) "STRM: RTSP/${if (config1.useTcp) "TCP" else "UDP"}:${config1.rtspPort}" else "STRM: RTSP/${if (config1.useTcp) "TCP" else "UDP"}"
            
            ptzPlayer1?.release()
            if (config1.autoConnect) {
                ptzPlayer1 = createPlayerInstance(1, config1)
                ptzPlayer1?.prepare(config1, tvStatusCam1, bgBlueCam1)
                ptzPlayer1?.play()
            } else {
                ptzPlayer1 = null
                bgBlueCam1.visibility = View.VISIBLE
                tvStatusCam1.text = "● STANDBY"
                tvStatusCam1.setTextColor(Color.GRAY)
            }
            testViscaConnection(viscaClient1, tvStatusCam1)
        }

        if (configChanged2) {
            currentConfig2 = config2
            viscaClient2 = ViscaClient(config2)
            tvNameCam2.text = config2.camName
            tvProtocolCam2.text = if (config2.showPort) "CTRL: ${config2.protocol}:${config2.controlPort}" else "CTRL: ${config2.protocol}"
            tvStreamCam2.text = if (config2.showPort) "STRM: RTSP/${if (config2.useTcp) "TCP" else "UDP"}:${config2.rtspPort}" else "STRM: RTSP/${if (config2.useTcp) "TCP" else "UDP"}"
            
            ptzPlayer2?.release()
            if (config2.autoConnect) {
                ptzPlayer2 = createPlayerInstance(2, config2)
                ptzPlayer2?.prepare(config2, tvStatusCam2, bgBlueCam2)
                ptzPlayer2?.play()
            } else {
                ptzPlayer2 = null
                bgBlueCam2.visibility = View.VISIBLE
                tvStatusCam2.text = "● STANDBY"
                tvStatusCam2.setTextColor(Color.GRAY)
            }
            testViscaConnection(viscaClient2, tvStatusCam2)
        }
    }

    private fun createPlayerInstance(index: Int, config: CameraConfig): PTZPlayer {
        val container = if (index == 1) videoContainerCam1 else videoContainerCam2
        // 強制回退到 Media3，直到解決 IJKPlayer 16KB Page Size 相容性問題
        return Media3PlayerWrapper(this, container) { handlePlayerError() }
    }

    private fun handlePlayerError() {
        reconnectHandler.removeCallbacksAndMessages(null)
        reconnectHandler.postDelayed({
            loadCameraConfigs(forceRefresh = true)
        }, 10000L)
    }

    private fun testViscaConnection(client: ViscaClient?, statusView: TextView) {
        client?.testConnection { success ->
            runOnUiThread {
                if (success) {
                    statusView.text = "● ONLINE"
                    statusView.setTextColor(Color.GREEN)
                } else {
                    statusView.text = "● OFFLINE"
                    statusView.setTextColor(Color.RED)
                }
            }
        }
    }

    private fun updateJoystickVisibility() {
        val enabled = repository.isVirtualJoystickEnabled()
        val visibility = if (enabled) View.VISIBLE else View.GONE
        joystickCam1.visibility = visibility
        joystickCam2.visibility = visibility
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if ((event.source and InputDevice.SOURCE_CLASS_JOYSTICK != 0) || 
            (event.source and InputDevice.SOURCE_GAMEPAD == InputDevice.SOURCE_GAMEPAD)) {
            when (keyCode) {
                keyC1P1 -> { viscaClient1?.sendPresetCommand(2, 1); return true }
                keyC1P2 -> { viscaClient1?.sendPresetCommand(2, 2); return true }
                keyC2P1 -> { viscaClient2?.sendPresetCommand(2, 1); return true }
                keyC2P2 -> { viscaClient2?.sendPresetCommand(2, 2); return true }
            }
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onGenericMotionEvent(event: MotionEvent): Boolean {
        if ((event.source and InputDevice.SOURCE_CLASS_JOYSTICK != 0) || 
            (event.source and InputDevice.SOURCE_GAMEPAD == InputDevice.SOURCE_GAMEPAD)) {
            if (event.action == MotionEvent.ACTION_MOVE) {
                handlePhysicalJoystick(event)
                return true
            }
        }
        return super.onGenericMotionEvent(event)
    }

    private fun handlePhysicalJoystick(event: MotionEvent) {
        fun getMappedVal(action: String, defaultAxis: Int): Float {
            val axisId = repository.getAxisMapping(action, defaultAxis)
            val raw = event.getAxisValue(axisId)
            return if (repository.isAxisInverted(action)) -raw else raw
        }

        val x1 = getMappedVal("c1_pan", MotionEvent.AXIS_X)
        val y1 = getMappedVal("c1_tilt", MotionEvent.AXIS_Y)
        val x2 = getMappedVal("c2_pan", MotionEvent.AXIS_Z)
        val y2 = getMappedVal("c2_tilt", MotionEvent.AXIS_RZ)
        val zoomVal = getMappedVal("c2_tilt", MotionEvent.AXIS_RZ)

        if (isCam1FullScreen) {
            processPtz(x1, y1, viscaClient1, 1)
            processZoom(zoomVal, viscaClient1)
            joystickCam1.updateHandleFromExternal(x1, y1)
            joystickCam2.updateHandleFromExternal(0f, zoomVal)
        } else if (isCam2FullScreen) {
            processPtz(x1, y1, viscaClient2, 2)
            processZoom(zoomVal, viscaClient2)
            joystickCam1.updateHandleFromExternal(x1, y1)
            joystickCam2.updateHandleFromExternal(0f, zoomVal)
        } else {
            processPtz(x1, y1, viscaClient1, 1)
            processPtz(x2, y2, viscaClient2, 2)
            joystickCam1.updateHandleFromExternal(x1, y1)
            joystickCam2.updateHandleFromExternal(x2, y2)
        }
    }

    private fun setupVirtualJoysticks() {
        joystickCam1.onMoveListener = { x, y ->
            when {
                isCam1FullScreen -> processPtz(x, y, viscaClient1, 1)
                isCam2FullScreen -> processPtz(x, y, viscaClient2, 2)
                else -> processPtz(x, y, viscaClient1, 1)
            }
        }
        joystickCam2.onMoveListener = { x, y ->
            when {
                isCam1FullScreen -> processZoom(y, viscaClient1)
                isCam2FullScreen -> processZoom(y, viscaClient2)
                else -> processPtz(x, y, viscaClient2, 2)
            }
        }
    }

    private fun setupPresetButtons() {
        findViewById<Button>(R.id.btnP1Cam1).setOnClickListener { viscaClient1?.sendPresetCommand(2, 1) }
        findViewById<Button>(R.id.btnP2Cam1).setOnClickListener { viscaClient1?.sendPresetCommand(2, 2) }
        findViewById<Button>(R.id.btnP1Cam2).setOnClickListener { viscaClient2?.sendPresetCommand(2, 1) }
        findViewById<Button>(R.id.btnP2Cam2).setOnClickListener { viscaClient2?.sendPresetCommand(2, 2) }
        
        findViewById<Button>(R.id.btnP1Cam1).setOnLongClickListener { viscaClient1?.sendPresetCommand(1, 1); showModeHint("P1 Saved"); true }
        findViewById<Button>(R.id.btnP2Cam1).setOnLongClickListener { viscaClient1?.sendPresetCommand(1, 2); showModeHint("P2 Saved"); true }
        findViewById<Button>(R.id.btnP1Cam2).setOnLongClickListener { viscaClient2?.sendPresetCommand(1, 1); showModeHint("P1 Saved"); true }
        findViewById<Button>(R.id.btnP2Cam2).setOnLongClickListener { viscaClient2?.sendPresetCommand(1, 2); showModeHint("P2 Saved"); true }
    }

    private fun applyExpoCurve(value: Float): Float {
        val deadzone = 0.15f
        if (abs(value) < deadzone) return 0f
        val normalized = (abs(value) - deadzone) / (1.0f - deadzone)
        val expoValue = normalized.pow(expoStrength)
        return expoValue * sign(value)
    }

    private fun processPtz(rawX: Float, rawY: Float, client: ViscaClient?, camIdx: Int) {
        val x = applyExpoCurve(rawX)
        val y = applyExpoCurve(rawY)
        val panMode = when { x < 0 -> 1; x > 0 -> 2; else -> 0 }
        val tiltMode = when { y < 0 -> 1; y > 0 -> 2; else -> 0 }
        val panSpeed = (abs(x) * 0x18).toInt().coerceIn(0, 0x18)
        val tiltSpeed = (abs(y) * 0x14).toInt().coerceIn(0, 0x14)
        val isChanged = if (camIdx == 1) {
            val changed = panMode != lastPan1 || tiltMode != lastTilt1
            lastPan1 = panMode; lastTilt1 = tiltMode
            changed
        } else {
            val changed = panMode != lastPan2 || tiltMode != lastTilt2
            lastPan2 = panMode; lastTilt2 = tiltMode
            changed
        }
        if (isChanged || (panMode != 0 || tiltMode != 0)) {
            client?.sendPtzCommand(panSpeed, tiltSpeed, panMode, tiltMode)
        }
    }

    private fun processZoom(rawZ: Float, client: ViscaClient?) {
        val z = applyExpoCurve(rawZ)
        val zoomMode = when { z < 0 -> 1; z > 0 -> 2; else -> 0 }
        val zoomSpeed = (abs(z) * 7).toInt().coerceIn(0, 7)
        if (zoomMode != lastZoom || zoomMode != 0) {
            lastZoom = zoomMode
            client?.sendZoomCommand(zoomMode, zoomSpeed)
        }
    }

    private fun setupGestures() {
        val gestureDetector1 = GestureDetector(this, object : GestureDetector.SimpleOnGestureListener() {
            override fun onDoubleTap(e: MotionEvent): Boolean { toggleFullScreen(1); return true }
        })
        val gestureDetector2 = GestureDetector(this, object : GestureDetector.SimpleOnGestureListener() {
            override fun onDoubleTap(e: MotionEvent): Boolean { toggleFullScreen(2); return true }
        })
        containerCam1.setOnTouchListener { v, event -> gestureDetector1.onTouchEvent(event); v.performClick(); true }
        containerCam2.setOnTouchListener { v, event -> gestureDetector2.onTouchEvent(event); v.performClick(); true }
    }

    private fun toggleFullScreen(camIndex: Int) {
        if (camIndex == 1) {
            if (isCam1FullScreen) {
                containerCam2.visibility = View.VISIBLE
                isCam1FullScreen = false
            } else {
                containerCam2.visibility = View.GONE
                isCam1FullScreen = true
                isCam2FullScreen = false
            }
        } else {
            if (isCam2FullScreen) {
                containerCam1.visibility = View.VISIBLE
                isCam2FullScreen = false
            } else {
                containerCam1.visibility = View.GONE
                isCam2FullScreen = true
                isCam1FullScreen = false
            }
        }
        stopAllCameras()
    }

    private fun showModeHint(message: String) {
        android.widget.Toast.makeText(this, message, android.widget.Toast.LENGTH_SHORT).show()
    }

    private fun toggleCameraConnection(index: Int) {
        if (index == 1) {
            if (ptzPlayer1?.isPlaying() == true) {
                ptzPlayer1?.release()
                ptzPlayer1 = null
                tvStatusCam1.text = "● STANDBY"
                tvStatusCam1.setTextColor(Color.GRAY)
                bgBlueCam1.visibility = View.VISIBLE
            } else {
                loadCameraConfigs(forceRefresh = true)
            }
        } else {
            if (ptzPlayer2?.isPlaying() == true) {
                ptzPlayer2?.release()
                ptzPlayer2 = null
                tvStatusCam2.text = "● STANDBY"
                tvStatusCam2.setTextColor(Color.GRAY)
                bgBlueCam2.visibility = View.VISIBLE
            } else {
                loadCameraConfigs(forceRefresh = true)
            }
        }
    }

    override fun onPause() { super.onPause(); stopAllCameras() }

    override fun onStop() { 
        super.onStop()
        usbJoystickManager.unregister()
        reconnectHandler.removeCallbacksAndMessages(null)
        watchdogHandler.removeCallbacksAndMessages(null)
        ptzPlayer1?.stop()
        ptzPlayer2?.stop()
        stopAllCameras() 
    }

    private fun stopAllCameras() {
        viscaClient1?.sendPtzCommand(0, 0, 0, 0)
        viscaClient1?.sendZoomCommand(0, 0)
        viscaClient2?.sendPtzCommand(0, 0, 0, 0)
        viscaClient2?.sendZoomCommand(0, 0)
        lastPan1 = 0; lastTilt1 = 0; lastPan2 = 0; lastTilt2 = 0; lastZoom = 0
    }

    override fun onDestroy() { 
        super.onDestroy()
        ptzPlayer1?.release()
        ptzPlayer2?.release()
    }
}
