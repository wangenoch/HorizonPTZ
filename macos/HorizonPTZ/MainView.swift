import SwiftUI
import AVKit

struct MainView: View {
    @State private var cam1Config = CameraRepository.shared.getConfig(index: 1)
    @State private var cam2Config = CameraRepository.shared.getConfig(index: 2)
    
    @State private var viscaClient1: ViscaClient?
    @State private var viscaClient2: ViscaClient?
    
    @State private var showSettings = false
    @State private var isAiLiveEnabled = true
    
    @State private var activeJoystickControl = 1 // 1: CAM1, 2: CAM2, 3: Both
    
    @State private var showVirtualJoysticks = CameraRepository.shared.isVirtualJoystickEnabled()
    
    @ObservedObject private var joystickManager = JoystickManager.shared
    @ObservedObject private var rgbClient = RGBLinkClient.shared
    @ObservedObject private var counterService = PeopleCounterService.shared
    
    @State private var leftTabSelection = 0
    @State private var rightTabSelection = 0
    
    @State private var cam1Sensitivity = CameraRepository.shared.getSensitivity(index: 1)
    @State private var cam2Sensitivity = CameraRepository.shared.getSensitivity(index: 2)
    
    @State private var switcherIp = CameraRepository.shared.getSwitcherIp()
    @State private var youtubeUrl = CameraRepository.shared.getYoutubeUrl()
    
    @State private var switcherLayoutMode: SwitcherLayoutMode = CameraRepository.shared.getSwitcherLayoutMode()
    @ObservedObject private var floatingWindowController = FloatingSwitcherWindowController.shared
    @State private var bottomSectionTab: Int = 0 // 0: Switcher, 1: YouTube Studio (for bottomConsole)
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Bar
            ZStack {
                // Left-aligned connection status
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "circle.fill")
                            .foregroundColor(joystickManager.isControllerConnected ? .green : .gray)
                            .font(.system(size: 8))
                        Text(joystickManager.isControllerConnected ? "控制器已連線: \(joystickManager.controllerName)" : "無硬體控制器")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                
                // Centered toggle button and layout selector
                HStack(spacing: 8) {
                    Button(action: {
                        toggleBothPanels()
                    }) {
                        Label("切換雙視窗", systemImage: "arrow.left.and.right.righttriangle.left.and.righttriangle.right")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    // Switcher Layout Selector
                    Picker("", selection: $switcherLayoutMode) {
                        ForEach(SwitcherLayoutMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.iconName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 145)
                    .help("切換導播機排版模式 (底部主控台 / 右側導播欄 / 獨立懸浮窗 / 單槽子母預覽)")
                    .onChange(of: switcherLayoutMode) { newMode in
                        CameraRepository.shared.setSwitcherLayoutMode(newMode)
                        if newMode == .floatingWindow {
                            FloatingSwitcherWindowController.shared.showWindow()
                        }
                    }
                    
                    if switcherLayoutMode == .floatingWindow {
                        Button(action: {
                            FloatingSwitcherWindowController.shared.toggleWindow()
                        }) {
                            Label(floatingWindowController.isVisible ? "導播窗" : "開啟導播窗", systemImage: "macwindow.on.rectangle")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(floatingWindowController.isVisible ? .accentColor : .secondary)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                
                // Right-aligned settings and controls
                HStack {
                    Spacer()
                    HStack(spacing: 10) {
                        HStack(spacing: 4) {
                            Text("實體搖桿:")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Picker("", selection: $activeJoystickControl) {
                                Text("CAM 01").tag(1)
                                Text("CAM 02").tag(2)
                                Text("雙機同步").tag(3)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 170)
                        }
                        
                        // Dual AI Engine Selector
                        Picker("", selection: $counterService.currentEngineMode) {
                            ForEach(AiEngineMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 175)
                        .help("選擇 AI 人數識別處理引擎 (Apple Vision 360° 或 CoreML YOLO 深度學習)")
                        .onChange(of: counterService.currentEngineMode) { _ in
                            counterService.saveCurrentSettings()
                        }
                        
                        Button(action: {
                            isAiLiveEnabled.toggle()
                        }) {
                            Label(isAiLiveEnabled ? "🟢 AI 追蹤 ON" : "👥 AI 追蹤 OFF", systemImage: isAiLiveEnabled ? "bolt.shield.fill" : "person.3.sequence.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(isAiLiveEnabled ? .green : .primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(isAiLiveEnabled ? Color.green.opacity(0.15) : Color.secondary.opacity(0.12))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            showSettings = true
                        }) {
                            Label("參數設定", systemImage: "gearshape")
                        }
                    }
                }
            }
            .padding(10)
            Divider()
            
            topSectionView
            
            Divider()
            
            bottomSectionView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            initializeClients()
            setupHardwareJoystick()
        }
        .onChange(of: leftTabSelection) { newValue in
            if newValue == 2 && rightTabSelection == 2 {
                rightTabSelection = 0
            }
        }
        .onChange(of: rightTabSelection) { newValue in
            if newValue == 2 && leftTabSelection == 2 {
                leftTabSelection = 0
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                cam1Config: $cam1Config,
                cam2Config: $cam2Config,
                onSave: {
                    showSettings = false
                    initializeClients()
                    switcherIp = CameraRepository.shared.getSwitcherIp()
                    youtubeUrl = CameraRepository.shared.getYoutubeUrl()
                    switcherLayoutMode = CameraRepository.shared.getSwitcherLayoutMode()
                },
                onCancel: {
                    showSettings = false
                }
            )
        }
        .frame(minWidth: 800, minHeight: 650)
    }
    
    private func getSensitivity(for index: Int) -> Double {
        return index == 1 ? cam1Sensitivity : cam2Sensitivity
    }
    
    private func setSensitivity(for index: Int, value: Double) {
        if index == 1 {
            cam1Sensitivity = value
            CameraRepository.shared.setSensitivity(index: 1, value: value)
        } else {
            cam2Sensitivity = value
            CameraRepository.shared.setSensitivity(index: 2, value: value)
        }
    }
    
    private func toggleBothPanels() {
        if leftTabSelection == 0 || rightTabSelection == 0 {
            leftTabSelection = 1
            rightTabSelection = 1
        } else {
            leftTabSelection = 0
            rightTabSelection = 0
        }
    }
    
    private func initializeClients() {
        viscaClient1 = ViscaClient(config: cam1Config)
        viscaClient2 = ViscaClient(config: cam2Config)
        showVirtualJoysticks = CameraRepository.shared.isVirtualJoystickEnabled()
    }
    
    private func setupHardwareJoystick() {
        joystickManager.onPanTiltUpdate = { pan, tilt in
            let expo = CameraRepository.shared.getExpoStrength()
            
            // Apply expo curve: y = sign(x) * |x|^expo
            let normPan = sign(pan) * pow(abs(pan), expo)
            let normTilt = sign(tilt) * pow(abs(tilt), expo)
            
            let panMode = pan > 0.15 ? 2 : (pan < -0.15 ? 1 : 0) // 1 left, 2 right
            let tiltMode = tilt > 0.15 ? 1 : (tilt < -0.15 ? 2 : 0) // 1 up, 2 down
            
            if activeJoystickControl == 1 || activeJoystickControl == 3 {
                let speedFactor = Float(self.getSensitivity(for: 1))
                let panSpeed = Int(abs(normPan) * 24 * speedFactor)
                let tiltSpeed = Int(abs(normTilt) * 20 * speedFactor)
                viscaClient1?.sendPtzCommand(panSpeed: panSpeed, tiltSpeed: tiltSpeed, panMode: panMode, tiltMode: tiltMode)
            }
            if activeJoystickControl == 2 || activeJoystickControl == 3 {
                let speedFactor = Float(self.getSensitivity(for: 2))
                let panSpeed = Int(abs(normPan) * 24 * speedFactor)
                let tiltSpeed = Int(abs(normTilt) * 20 * speedFactor)
                viscaClient2?.sendPtzCommand(panSpeed: panSpeed, tiltSpeed: tiltSpeed, panMode: panMode, tiltMode: tiltMode)
            }
        }
        
        joystickManager.onZoomUpdate = { mode, speed in
            if activeJoystickControl == 1 || activeJoystickControl == 3 {
                viscaClient1?.sendZoomCommand(mode: mode, speed: speed)
            }
            if activeJoystickControl == 2 || activeJoystickControl == 3 {
                viscaClient2?.sendZoomCommand(mode: mode, speed: speed)
            }
        }
    }
    
    @ViewBuilder
    private var topSectionView: some View {
        switch switcherLayoutMode {
        case .rightSidebar:
            HStack(spacing: 12) {
                tabbedPanel(index: 1, selection: $leftTabSelection, config: cam1Config, client: viscaClient1)
                tabbedPanel(index: 2, selection: $rightTabSelection, config: cam2Config, client: viscaClient2)
                SwitcherControlView(layoutStyle: .rightSidebar, isAiLiveEnabled: $isAiLiveEnabled)
                    .frame(width: 235)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)
        default:
            HStack(spacing: 12) {
                tabbedPanel(index: 1, selection: $leftTabSelection, config: cam1Config, client: viscaClient1)
                tabbedPanel(index: 2, selection: $rightTabSelection, config: cam2Config, client: viscaClient2)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)
        }
    }
    
    @ViewBuilder
    private var bottomSectionView: some View {
        switch switcherLayoutMode {
        case .bottomConsole:
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Picker("", selection: $bottomSectionTab) {
                        Label("🎛️ 導播機控制台", systemImage: "slider.horizontal.below.rectangle").tag(0)
                        Label("📺 YouTube 直播主控台", systemImage: "play.rectangle").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                    
                    Spacer()
                    
                    if bottomSectionTab == 0 {
                        Text("💡 廣播級寬幅控制台：支援 PGM/PST 獨立雙母線、轉場特效與 PIP 子母畫面")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(nsColor: .windowBackgroundColor))
                
                Divider()
                
                if bottomSectionTab == 0 {
                    SwitcherControlView(layoutStyle: .bottomConsole, isAiLiveEnabled: $isAiLiveEnabled)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    YouTubeStudioDashboardView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        default:
            YouTubeStudioDashboardView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private func tabbedPanel(index: Int, selection: Binding<Int>, config: CameraConfig, client: ViscaClient?) -> some View {
        let isPgm = (rgbClient.pgmSource == (index - 1))
        let isPst = (rgbClient.pstSource == (index - 1))
        
        return VStack(spacing: 6) {
            // Header with Switcher & Tally Badge
            HStack(spacing: 8) {
                Text(selection.wrappedValue == 0 ? config.camName : (selection.wrappedValue == 1 ? "網頁監控 0\(index)" : "導播控制 0\(index)"))
                    .font(.system(size: 13, weight: .bold))
                
                if isPgm {
                    Text("🔴 ON AIR")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .cornerRadius(4)
                } else if isPst {
                    Text("🟢 PREVIEW")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green)
                        .cornerRadius(4)
                }
                
                Spacer()
                
                if selection.wrappedValue == 0 {
                    Button(action: {
                        isAiLiveEnabled.toggle()
                    }) {
                        Label(isAiLiveEnabled ? "AI: ON" : "AI: OFF", systemImage: isAiLiveEnabled ? "sparkles" : "person.3")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(isAiLiveEnabled ? .green : .secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(isAiLiveEnabled ? Color.green.opacity(0.15) : Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    
                    Text(config.ipAddress)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.trailing, 4)
                }
                
                Picker("", selection: selection) {
                    Text("相機").tag(0)
                    Text("網頁").tag(1)
                    Text("導播機").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
            .padding(.horizontal, 4)
            
            // Content
            if selection.wrappedValue == 0 {
                cameraContent(index: index, config: config, client: client)
            } else if selection.wrappedValue == 1 {
                WebBrowserComponent(initialUrl: "http://\(config.ipAddress)")
                    .aspectRatio(16/9, contentMode: .fit)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            } else {
                if switcherLayoutMode == .embeddedSlot {
                    SwitcherControlView(layoutStyle: .embedded(cameraIndex: index), isAiLiveEnabled: $isAiLiveEnabled)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                } else {
                    SwitcherControlView(layoutStyle: .standard, isAiLiveEnabled: $isAiLiveEnabled)
                        .aspectRatio(16/9, contentMode: .fit)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }
            }
        }
    }
    
    private func cameraContent(index: Int, config: CameraConfig, client: ViscaClient?) -> some View {
        let isPgm = (rgbClient.pgmSource == (index - 1))
        let isPst = (rgbClient.pstSource == (index - 1))
        
        let tallyColor: Color = isPgm ? .red : (isPst ? .green : Color.secondary.opacity(0.3))
        let tallyLineWidth: CGFloat = (isPgm || isPst) ? 3.5 : 1.0
        
        return VStack(spacing: 6) {
            // Video Player Area
            ZStack {
                PlayerView(rtspUrl: config.rtspUrl, index: index, isAiEnabled: $isAiLiveEnabled)
                    .id(config.rtspUrl) // Re-create view on URL change
                    .aspectRatio(16/9, contentMode: .fit)
                    .background(Color.black)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(tallyColor, lineWidth: tallyLineWidth)
                            .shadow(color: isPgm ? Color.red.opacity(0.6) : (isPst ? Color.green.opacity(0.6) : Color.clear), radius: (isPgm || isPst) ? 6 : 0)
                    )
                
                // Virtual Joysticks overlay
                if showVirtualJoysticks {
                    HStack {
                        Spacer()
                        VirtualJoystickView(
                            title: "PTZ 控制",
                            onJoystickMove: { x, y in
                                handleVirtualJoystickUpdate(index: index, client: client, x: x, y: y)
                            },
                            onJoystickRelease: {
                                client?.sendPtzCommand(panSpeed: 0, tiltSpeed: 0, panMode: 0, tiltMode: 0)
                            }
                        )
                        .padding(10)
                        .background(Color.black.opacity(0.45))
                        .cornerRadius(12)
                        .padding(.trailing, 10)
                        .padding(.bottom, 10)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            
            // Camera control bar
            HStack(spacing: 12) {
                // Zoom controls
                HStack(spacing: 4) {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 11))
                        .padding(5)
                        .background(Color(nsColor: .controlColor))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                        .pressAndHoldAction(
                            onPress: { client?.sendZoomCommand(mode: 1, speed: 4) },
                            onRelease: { client?.sendZoomCommand(mode: 0, speed: 0) }
                        )
                        .help("拉近 (Zoom In)")
                    
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 11))
                        .padding(5)
                        .background(Color(nsColor: .controlColor))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                        .pressAndHoldAction(
                            onPress: { client?.sendZoomCommand(mode: 2, speed: 4) },
                            onRelease: { client?.sendZoomCommand(mode: 0, speed: 0) }
                        )
                        .help("拉遠 (Zoom Out)")
                }
                
                // Sensitivity Slider
                HStack(spacing: 4) {
                    Image(systemName: "gauge.medium")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("\(Int(getSensitivity(for: index) * 100))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 32, alignment: .leading)
                    
                    Slider(
                        value: Binding(
                            get: { getSensitivity(for: index) },
                            set: { newValue in setSensitivity(for: index, value: newValue) }
                        ),
                        in: 0.1...1.0,
                        step: 0.05
                    )
                    .frame(width: 75)
                    .controlSize(.mini)
                }
                
                Spacer()
                
                // Presets
                HStack(spacing: 4) {
                    Text("預設點:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    ForEach(1...3, id: \.self) { preset in
                        Button("P\(preset)") {
                            client?.sendPresetCommand(mode: 2, presetIndex: preset)
                        }
                        .buttonStyle(.bordered)
                        .help("呼叫預設點 \(preset)")
                        .contextMenu {
                            Button("儲存此預設點 \(preset)") {
                                client?.sendPresetCommand(mode: 1, presetIndex: preset)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }
    
    private func handleVirtualJoystickUpdate(index: Int, client: ViscaClient?, x: CGFloat, y: CGFloat) {
        let maxPanSpeed: CGFloat = 24
        let maxTiltSpeed: CGFloat = 20
        
        let speedFactor = CGFloat(getSensitivity(for: index))
        let panSpeed = Int(abs(x) * maxPanSpeed * speedFactor)
        let tiltSpeed = Int(abs(y) * maxTiltSpeed * speedFactor)
        
        let panMode = x > 0.15 ? 2 : (x < -0.15 ? 1 : 0) // 1: left, 2: right
        let tiltMode = y > 0.15 ? 1 : (y < -0.15 ? 2 : 0) // 1: up, 2: down
        
        client?.sendPtzCommand(panSpeed: panSpeed, tiltSpeed: tiltSpeed, panMode: panMode, tiltMode: tiltMode)
    }
}

// Press and hold button helper modifier
struct PressAndHoldModifier: ViewModifier {
    var onPress: () -> Void
    var onRelease: () -> Void
    
    @GestureState private var isPressing = false
    
    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressing) { _, state, _ in
                        if !state {
                            state = true
                            onPress()
                        }
                    }
                    .onEnded { _ in
                        onRelease()
                    }
            )
    }
}

extension View {
    func pressAndHoldAction(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        modifier(PressAndHoldModifier(onPress: onPress, onRelease: onRelease))
    }
}
