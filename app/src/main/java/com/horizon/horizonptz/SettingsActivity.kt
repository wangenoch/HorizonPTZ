package com.horizon.horizonptz

import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.SwitchCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.google.android.material.tabs.TabLayout
import com.horizon.horizonptz.camera.CameraConfig
import com.horizon.horizonptz.camera.CameraRepository
import com.horizon.horizonptz.camera.UsbJoystickManager
import com.horizon.horizonptz.camera.ViscaClient
import com.horizon.horizonptz.config.AppConfig
import kotlin.math.abs

class SettingsActivity : AppCompatActivity() {

    private lateinit var repository: CameraRepository
    private lateinit var usbJoystickManager: UsbJoystickManager
    
    private lateinit var tabLayout: TabLayout
    private lateinit var layoutCam1Settings: LinearLayout
    private lateinit var layoutCam2Settings: LinearLayout
    private lateinit var layoutJoystickSettings: LinearLayout

    private lateinit var editCam1Name: EditText
    private lateinit var editCam1Ip: EditText
    private lateinit var editCam1RtspPath: EditText
    private lateinit var editCam1ControlPort: EditText
    private lateinit var editCam1RtspPort: EditText
    private lateinit var editCam1Account: EditText
    private lateinit var editCam1Password: EditText
    private lateinit var switchCam1Tcp: SwitchCompat
    private lateinit var switchCam1ShowPort: SwitchCompat
    private lateinit var switchCam1AutoConnect: SwitchCompat
    
    private lateinit var editCam2Name: EditText
    private lateinit var editCam2Ip: EditText
    private lateinit var editCam2RtspPath: EditText
    private lateinit var editCam2ControlPort: EditText
    private lateinit var editCam2RtspPort: EditText
    private lateinit var editCam2Account: EditText
    private lateinit var editCam2Password: EditText
    private lateinit var switchCam2Tcp: SwitchCompat
    private lateinit var switchCam2ShowPort: SwitchCompat
    private lateinit var switchCam2AutoConnect: SwitchCompat
    private lateinit var spinnerCam1Engine: Spinner
    private lateinit var spinnerCam2Engine: Spinner
    private lateinit var spinnerCam1Quality: Spinner
    private lateinit var spinnerCam2Quality: Spinner

    private lateinit var switchVirtualJoystick: SwitchCompat
    private lateinit var seekExpo: SeekBar
    private lateinit var tvActiveAxis: TextView
    
    private lateinit var tvCam1Url: TextView
    private lateinit var tvCam2Url: TextView

    private lateinit var previewJoystickL: com.horizon.horizonptz.ui.VirtualJoystickView
    private lateinit var previewJoystickR: com.horizon.horizonptz.ui.VirtualJoystickView

    private lateinit var btnTestCam1: Button
    private lateinit var btnTestCam2: Button

    private lateinit var tvSummaryC1Ptz: TextView
    private lateinit var tvSummaryC1Vid: TextView
    private lateinit var tvSummaryC2Ptz: TextView
    private lateinit var tvSummaryC2Vid: TextView

    private var bindingAction: String? = null
    private var bindingAxisAction: String? = null
    
    private lateinit var btnMap1P1: Button
    private lateinit var btnMap1P2: Button
    private lateinit var btnMap2P1: Button
    private lateinit var btnMap2P2: Button

    private lateinit var btnAxisC1Pan: Button
    private lateinit var btnAxisC1Tilt: Button
    private lateinit var btnAxisC2Pan: Button
    private lateinit var btnAxisC2Tilt: Button

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Hide system navigation and status bars (Time, Battery, etc.)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowInsetsControllerCompat(window, window.decorView).apply {
            hide(WindowInsetsCompat.Type.systemBars())
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }

        setContentView(R.layout.activity_settings)

        repository = (application as HorizonPTZApp).repository

        usbJoystickManager = UsbJoystickManager(this) { device ->
            Toast.makeText(this, "Joystick Ready: ${device.deviceName}", Toast.LENGTH_SHORT).show()
        }

        tabLayout = findViewById(R.id.tabLayout)
        layoutCam1Settings = findViewById(R.id.layoutCam1Settings)
        layoutCam2Settings = findViewById(R.id.layoutCam2Settings)
        layoutJoystickSettings = findViewById(R.id.layoutJoystickSettings)
        
        // Cam 1
        editCam1Name = findViewById(R.id.editCam1Name)
        editCam1Ip = findViewById(R.id.editCam1Ip)
        editCam1RtspPath = findViewById(R.id.editCam1RtspPath)
        editCam1ControlPort = findViewById(R.id.editCam1ControlPort)
        editCam1RtspPort = findViewById(R.id.editCam1RtspPort)
        editCam1Account = findViewById(R.id.editCam1Account)
        editCam1Password = findViewById(R.id.editCam1Password)
        switchCam1Tcp = findViewById(R.id.switchCam1Tcp)
        switchCam1ShowPort = findViewById(R.id.switchCam1ShowPort)
        switchCam1AutoConnect = findViewById(R.id.switchCam1AutoConnect)
        tvCam1Url = findViewById(R.id.tvCam1Url)
        btnTestCam1 = findViewById(R.id.btnTestCam1)

        previewJoystickL = findViewById(R.id.previewJoystickL)
        previewJoystickR = findViewById(R.id.previewJoystickR)

        // Cam 2
        editCam2Name = findViewById(R.id.editCam2Name)
        editCam2Ip = findViewById(R.id.editCam2Ip)
        editCam2RtspPath = findViewById(R.id.editCam2RtspPath)
        editCam2ControlPort = findViewById(R.id.editCam2ControlPort)
        editCam2RtspPort = findViewById(R.id.editCam2RtspPort)
        editCam2Account = findViewById(R.id.editCam2Account)
        editCam2Password = findViewById(R.id.editCam2Password)
        switchCam2Tcp = findViewById(R.id.switchCam2Tcp)
        switchCam2ShowPort = findViewById(R.id.switchCam2ShowPort)
        switchCam2AutoConnect = findViewById(R.id.switchCam2AutoConnect)
        spinnerCam1Engine = findViewById(R.id.spinnerCam1Engine)
        spinnerCam2Engine = findViewById(R.id.spinnerCam2Engine)
        spinnerCam1Quality = findViewById(R.id.spinnerCam1Quality)
        spinnerCam2Quality = findViewById(R.id.spinnerCam2Quality)
        tvCam2Url = findViewById(R.id.tvCam2Url)
        btnTestCam2 = findViewById(R.id.btnTestCam2)

        switchVirtualJoystick = findViewById(R.id.switchVirtualJoystick)
        seekExpo = findViewById(R.id.seekExpo)
        tvActiveAxis = findViewById(R.id.tvActiveAxis)

        tvSummaryC1Ptz = findViewById(R.id.tvStatusIndicatorsCam1)
        tvSummaryC1Vid = findViewById(R.id.tvStatusSummaryCam1)
        tvSummaryC2Ptz = findViewById(R.id.tvStatusIndicatorsCam2)
        tvSummaryC2Vid = findViewById(R.id.tvStatusSummaryCam2)

        btnMap1P1 = findViewById(R.id.btnBindC1P1)
        btnMap1P2 = findViewById(R.id.btnBindC1P2)
        btnMap2P1 = findViewById(R.id.btnBindC2P1)
        btnMap2P2 = findViewById(R.id.btnBindC2P2)

        btnAxisC1Pan = findViewById(R.id.btnBindLX)
        btnAxisC1Tilt = findViewById(R.id.btnBindLY)
        btnAxisC2Pan = findViewById(R.id.btnBindRX)
        btnAxisC2Tilt = findViewById(R.id.btnBindRY)

        setupTabs()
        setupEngineSpinners()
        setupUrlWatchers()
        setupMappingClickListeners()
        setupAxisMappingClickListeners()

        findViewById<ImageButton>(R.id.btnClose).setOnClickListener { finish() }
        btnTestCam1.setOnClickListener { testConnection(1) }
        btnTestCam2.setOnClickListener { testConnection(2) }
        findViewById<Button>(R.id.btnSave).setOnClickListener { saveSettings() }

        loadSettings()
    }

    private fun setupEngineSpinners() {
        val engines = listOf("Media3", "IJKPlayer", "WebRTC")
        val engineAdapter = ArrayAdapter(this, android.R.layout.simple_spinner_dropdown_item, engines)
        spinnerCam1Engine.adapter = engineAdapter
        spinnerCam2Engine.adapter = engineAdapter
        
        val qualities = listOf("High (av0)", "Low (av1)")
        val qualityAdapter = ArrayAdapter(this, android.R.layout.simple_spinner_dropdown_item, qualities)
        spinnerCam1Quality.adapter = qualityAdapter
        spinnerCam2Quality.adapter = qualityAdapter

        val config1 = repository.getConfig(1)
        val config2 = repository.getConfig(2)
        setSpinnerToValue(spinnerCam1Engine, config1.engine)
        setSpinnerToValue(spinnerCam2Engine, config2.engine)
        spinnerCam1Quality.setSelection(if (config1.rtspPath.contains("av1")) 1 else 0)
        spinnerCam2Quality.setSelection(if (config2.rtspPath.contains("av1")) 1 else 0)
    }

    private fun setupUrlWatchers() {
        val watcher = object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: Editable?) { updateUrlPreview() }
        }
        editCam1Ip.addTextChangedListener(watcher)
        editCam1RtspPath.addTextChangedListener(watcher)
        editCam2Ip.addTextChangedListener(watcher)
        editCam2RtspPath.addTextChangedListener(watcher)
        switchCam1ShowPort.setOnCheckedChangeListener { _, _ -> updateUrlPreview() }
        switchCam2ShowPort.setOnCheckedChangeListener { _, _ -> updateUrlPreview() }
    }

    private fun setupTabs() {
        tabLayout.addTab(tabLayout.newTab().setText("Cam 1"))
        tabLayout.addTab(tabLayout.newTab().setText("Cam 2"))
        tabLayout.addTab(tabLayout.newTab().setText("Joysticks"))

        tabLayout.addOnTabSelectedListener(object : TabLayout.OnTabSelectedListener {
            override fun onTabSelected(tab: TabLayout.Tab?) {
                layoutCam1Settings.visibility = View.GONE
                layoutCam2Settings.visibility = View.GONE
                layoutJoystickSettings.visibility = View.GONE
                when (tab?.position) {
                    0 -> layoutCam1Settings.visibility = View.VISIBLE
                    1 -> layoutCam2Settings.visibility = View.VISIBLE
                    2 -> layoutJoystickSettings.visibility = View.VISIBLE
                }
            }
            override fun onTabUnselected(tab: TabLayout.Tab?) {}
            override fun onTabReselected(tab: TabLayout.Tab?) {}
        })
    }

    private fun setupAxisMappingClickListeners() {
        btnAxisC1Pan.setOnClickListener { startBindingAxis("c1_pan") }
        btnAxisC1Tilt.setOnClickListener { startBindingAxis("c1_tilt") }
        btnAxisC2Pan.setOnClickListener { startBindingAxis("c2_pan") }
        btnAxisC2Tilt.setOnClickListener { startBindingAxis("c2_tilt") }
    }

    private fun startBindingAxis(action: String) {
        bindingAxisAction = action
        tvActiveAxis.text = "MOVE STICK FOR: ${action.uppercase()}"
        tvActiveAxis.setTextColor(android.graphics.Color.RED)
    }

    private fun setupMappingClickListeners() {
        btnMap1P1.setOnClickListener { startBinding("C1P1") }
        btnMap1P2.setOnClickListener { startBinding("C1P2") }
        btnMap2P1.setOnClickListener { startBinding("C2P1") }
        btnMap2P2.setOnClickListener { startBinding("C2P2") }
    }

    private fun startBinding(action: String) {
        bindingAction = action
        Toast.makeText(this, "Press Gamepad Button for $action", Toast.LENGTH_SHORT).show()
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (bindingAction != null && (event.source and InputDevice.SOURCE_GAMEPAD == InputDevice.SOURCE_GAMEPAD)) {
            repository.setKeyCode(bindingAction!!, keyCode)
            Toast.makeText(this, "$bindingAction Bound to $keyCode", Toast.LENGTH_SHORT).show()
            bindingAction = null
            updateMappingButtons()
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onGenericMotionEvent(event: MotionEvent): Boolean {
        if (event.source and InputDevice.SOURCE_CLASS_JOYSTICK != 0 && event.action == MotionEvent.ACTION_MOVE) {
            if (bindingAxisAction != null) {
                for (axis in 0..48) {
                    val value = event.getAxisValue(axis)
                    if (abs(value) > 0.8f) {
                        repository.saveAxisMapping(bindingAxisAction!!, axis, value < 0)
                        Toast.makeText(this, "Bound to Axis $axis", Toast.LENGTH_SHORT).show()
                        bindingAxisAction = null
                        tvActiveAxis.text = "All systems ready"
                        tvActiveAxis.setTextColor(android.graphics.Color.GRAY)
                        updateAxisButtons()
                        break
                    }
                }
            }
            
            fun getVal(a: String, d: Int) : Float {
                val id = repository.getAxisMapping(a, d)
                val r = event.getAxisValue(id)
                return if (repository.isAxisInverted(a)) -r else r
            }
            previewJoystickL.updateHandleFromExternal(getVal("c1_pan", MotionEvent.AXIS_X), getVal("c1_tilt", MotionEvent.AXIS_Y))
            previewJoystickR.updateHandleFromExternal(getVal("c2_pan", MotionEvent.AXIS_Z), getVal("c2_tilt", MotionEvent.AXIS_RZ))
            
            val sb = StringBuilder("Active Axes: ")
            for (i in 0..48) {
                if (abs(event.getAxisValue(i)) > 0.1f) sb.append("$i ")
            }
            tvActiveAxis.text = sb.toString()
        }
        return super.onGenericMotionEvent(event)
    }

    private fun loadSettings() {
        val config1 = repository.getConfig(1)
        editCam1Name.setText(config1.camName)
        editCam1Ip.setText(config1.ipAddress)
        editCam1RtspPath.setText(config1.rtspPath)
        editCam1ControlPort.setText(config1.controlPort.toString())
        editCam1RtspPort.setText(config1.rtspPort.toString())
        editCam1Account.setText(config1.account)
        editCam1Password.setText(config1.password)
        switchCam1Tcp.isChecked = config1.useTcp
        switchCam1ShowPort.isChecked = config1.showPort
        switchCam1AutoConnect.isChecked = config1.autoConnect

        val config2 = repository.getConfig(2)
        editCam2Name.setText(config2.camName)
        editCam2Ip.setText(config2.ipAddress)
        editCam2RtspPath.setText(config2.rtspPath)
        editCam2ControlPort.setText(config2.controlPort.toString())
        editCam2RtspPort.setText(config2.rtspPort.toString())
        editCam2Account.setText(config2.account)
        editCam2Password.setText(config2.password)
        switchCam2Tcp.isChecked = config2.useTcp
        switchCam2ShowPort.isChecked = config2.showPort
        switchCam2AutoConnect.isChecked = config2.autoConnect

        switchVirtualJoystick.isChecked = repository.isVirtualJoystickEnabled()
        seekExpo.progress = ((repository.getExpoStrength() - 0.5f) * 10).toInt()
        
        updateUrlPreview()
        updateMappingButtons()
        updateAxisButtons()
        testConnection(1)
        testConnection(2)
    }

    private fun updateAxisButtons() {
        btnAxisC1Pan.text = "LX: Axis ${repository.getAxisMapping("c1_pan", 0)}"
        btnAxisC1Tilt.text = "LY: Axis ${repository.getAxisMapping("c1_tilt", 1)}"
        btnAxisC2Pan.text = "RX: Axis ${repository.getAxisMapping("c2_pan", 11)}"
        btnAxisC2Tilt.text = "RY: Axis ${repository.getAxisMapping("c2_tilt", 14)}"
    }

    private fun setSpinnerToValue(spinner: Spinner, value: String) {
        val adapter = spinner.adapter
        if (adapter != null) {
            for (i in 0 until adapter.count) {
                if (adapter.getItem(i).toString().equals(value, ignoreCase = true)) {
                    spinner.setSelection(i)
                    return
                }
            }
        }
        spinner.setSelection(0)
    }

    private fun updateUrlPreview() {
        val ip1 = editCam1Ip.text.toString()
        val path1 = editCam1RtspPath.text.toString()
        tvCam1Url.text = "URL: rtsp://admin:***@$ip1${if (path1.startsWith("/")) "" else "/"}$path1"
        
        val ip2 = editCam2Ip.text.toString()
        val path2 = editCam2RtspPath.text.toString()
        tvCam2Url.text = "URL: rtsp://admin:***@$ip2${if (path2.startsWith("/")) "" else "/"}$path2"
    }

    private fun updateMappingButtons() {
        fun formatKey(a: String, d: Int) = "$a: ${KeyEvent.keyCodeToString(repository.getKeyCode(a, d)).replace("KEYCODE_","")}"
        btnMap1P1.text = formatKey("C1P1", KeyEvent.KEYCODE_BUTTON_A)
        btnMap1P2.text = formatKey("C1P2", KeyEvent.KEYCODE_BUTTON_B)
        btnMap2P1.text = formatKey("C2P1", KeyEvent.KEYCODE_BUTTON_X)
        btnMap2P2.text = formatKey("C2P2", KeyEvent.KEYCODE_BUTTON_Y)
    }

    private fun testConnection(camIdx: Int) {
        val config = repository.getConfig(camIdx)
        val ptzView = if (camIdx == 1) tvSummaryC1Ptz else tvSummaryC2Ptz
        val vidView = if (camIdx == 1) tvSummaryC1Vid else tvSummaryC2Vid
        
        ViscaClient(config).testConnection { success ->
            runOnUiThread {
                ptzView.text = "PTZ:${if (success) "●" else "○"}"
                ptzView.setTextColor(if (success) android.graphics.Color.GREEN else android.graphics.Color.RED)
            }
        }
        
        Thread {
            try {
                val socket = java.net.Socket()
                socket.connect(java.net.InetSocketAddress(config.ipAddress, config.rtspPort), 2000)
                socket.close()
                runOnUiThread {
                    vidView.text = "${config.camName} VID:●"
                    vidView.setTextColor(android.graphics.Color.GREEN)
                }
            } catch (e: Exception) {
                runOnUiThread {
                    vidView.text = "${config.camName} VID:○"
                    vidView.setTextColor(android.graphics.Color.RED)
                }
            }
        }.start()
    }

    private fun saveSettings() {
        val name1 = editCam1Name.text.toString().takeIf { it.isNotBlank() } ?: "CAM 01"
        val ip1 = editCam1Ip.text.toString().takeIf { it.isNotBlank() } ?: AppConfig.DEFAULT_IP_CAM1
        val cPort1 = editCam1ControlPort.text.toString().toIntOrNull() ?: AppConfig.DEFAULT_VISCA_PORT
        val rPort1 = editCam1RtspPort.text.toString().toIntOrNull() ?: AppConfig.DEFAULT_RTSP_PORT
        val acc1 = editCam1Account.text.toString().takeIf { it.isNotBlank() } ?: AppConfig.DEFAULT_ACCOUNT
        val pwd1 = editCam1Password.text.toString().takeIf { it.isNotBlank() } ?: AppConfig.DEFAULT_PASSWORD
        val path1 = if (spinnerCam1Quality.selectedItemPosition == 0) "/live/av0" else "/live/av1"

        repository.saveConfig(1, CameraConfig(
            camName = name1, ipAddress = ip1, controlPort = cPort1, rtspPort = rPort1, rtspUrl = "",
            account = acc1, password = pwd1, useTcp = switchCam1Tcp.isChecked, rtspPath = path1, 
            showPort = switchCam1ShowPort.isChecked, autoConnect = switchCam1AutoConnect.isChecked,
            engine = spinnerCam1Engine.selectedItem.toString()
        ))

        val name2 = editCam2Name.text.toString().takeIf { it.isNotBlank() } ?: "CAM 02"
        val ip2 = editCam2Ip.text.toString().takeIf { it.isNotBlank() } ?: AppConfig.DEFAULT_IP_CAM2
        val cPort2 = editCam2ControlPort.text.toString().toIntOrNull() ?: AppConfig.DEFAULT_VISCA_PORT
        val rPort2 = editCam2RtspPort.text.toString().toIntOrNull() ?: AppConfig.DEFAULT_RTSP_PORT
        val acc2 = editCam2Account.text.toString().takeIf { it.isNotBlank() } ?: AppConfig.DEFAULT_ACCOUNT
        val pwd2 = editCam2Password.text.toString().takeIf { it.isNotBlank() } ?: AppConfig.DEFAULT_PASSWORD
        val path2 = if (spinnerCam2Quality.selectedItemPosition == 0) "/live/av0" else "/live/av1"

        repository.saveConfig(2, CameraConfig(
            camName = name2, ipAddress = ip2, controlPort = cPort2, rtspPort = rPort2, rtspUrl = "",
            account = acc2, password = pwd2, useTcp = switchCam2Tcp.isChecked, rtspPath = path2, 
            showPort = switchCam2ShowPort.isChecked, autoConnect = switchCam2AutoConnect.isChecked,
            engine = spinnerCam2Engine.selectedItem.toString()
        ))

        repository.setVirtualJoystickEnabled(switchVirtualJoystick.isChecked)
        repository.setExpoStrength(seekExpo.progress / 10f + 0.5f)
        Toast.makeText(this, "Saved!", Toast.LENGTH_SHORT).show()
        finish()
    }

    override fun onStart() { super.onStart(); usbJoystickManager.register() }
    override fun onStop() { super.onStop(); usbJoystickManager.unregister() }
}
