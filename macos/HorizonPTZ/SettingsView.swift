import SwiftUI

struct SettingsView: View {
    @Binding var cam1Config: CameraConfig
    @Binding var cam2Config: CameraConfig
    
    @State private var localCam1: CameraConfig
    @State private var localCam2: CameraConfig
    
    @State private var cam1ControlPortStr: String
    @State private var cam1RtspPortStr: String
    @State private var cam2ControlPortStr: String
    @State private var cam2RtspPortStr: String
    
    @State private var selectedAiEngine: AiEngineMode
    @State private var confidenceThresh: Float
    @State private var minObjSize: Float
    @State private var fpsVal: Int
    @State private var alphaVal: Float
    @State private var distVal: Float
    
    @State private var isReIdOn: Bool
    @State private var reIdSimVal: Float
    
    @State private var expoStrength: Float
    @State private var switcherIp: String
    @State private var switcherLayoutMode: SwitcherLayoutMode
    @State private var youtubeChannelId: String
    @State private var youtubeStreamKey: String
    
    var onSave: () -> Void
    var onCancel: () -> Void
    
    init(cam1Config: Binding<CameraConfig>, cam2Config: Binding<CameraConfig>, onSave: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self._cam1Config = cam1Config
        self._cam2Config = cam2Config
        let c1 = cam1Config.wrappedValue
        let c2 = cam2Config.wrappedValue
        self._localCam1 = State(initialValue: c1)
        self._localCam2 = State(initialValue: c2)
        
        self._cam1ControlPortStr = State(initialValue: String(c1.controlPort))
        self._cam1RtspPortStr = State(initialValue: String(c1.rtspPort))
        self._cam2ControlPortStr = State(initialValue: String(c2.controlPort))
        self._cam2RtspPortStr = State(initialValue: String(c2.rtspPort))
        
        let counter = PeopleCounterService.shared
        self._selectedAiEngine = State(initialValue: counter.currentEngineMode)
        self._confidenceThresh = State(initialValue: counter.confidenceThreshold)
        self._minObjSize = State(initialValue: counter.minObjectSize)
        self._fpsVal = State(initialValue: counter.samplingFps)
        self._alphaVal = State(initialValue: counter.trackingAlpha)
        self._distVal = State(initialValue: counter.maxMotionDistance)
        self._isReIdOn = State(initialValue: counter.isReIdEnabled)
        self._reIdSimVal = State(initialValue: counter.reIdSimilarity)
        
        self._expoStrength = State(initialValue: CameraRepository.shared.getExpoStrength())
        self._switcherIp = State(initialValue: CameraRepository.shared.getSwitcherIp())
        self._switcherLayoutMode = State(initialValue: CameraRepository.shared.getSwitcherLayoutMode())
        self._youtubeChannelId = State(initialValue: CameraRepository.shared.getYoutubeChannelId())
        self._youtubeStreamKey = State(initialValue: CameraRepository.shared.getYoutubeStreamKey())
        self.onSave = onSave
        self.onCancel = onCancel
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Title
            HStack {
                Text("HorizonPTZ 系統參數設定")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 10)
            
            TabView {
                // AI Engine Settings (REDESIGNED WITH RE-ID)
                aiEngineTab()
                    .tabItem {
                        Label("AI 辨識引擎", systemImage: "sparkles.tv")
                    }
                
                // CAM 1 Settings
                cameraTab(title: "CAM 01 參數設定", config: $localCam1, controlPortStr: $cam1ControlPortStr, rtspPortStr: $cam1RtspPortStr)
                    .tabItem {
                        Label("CAM 01 相機", systemImage: "video")
                    }
                
                // CAM 2 Settings
                cameraTab(title: "CAM 02 參數設定", config: $localCam2, controlPortStr: $cam2ControlPortStr, rtspPortStr: $cam2RtspPortStr)
                    .tabItem {
                        Label("CAM 02 相機", systemImage: "video.fill")
                    }
                
                // Joystick settings
                joystickTab()
                    .tabItem {
                        Label("搖桿設定", systemImage: "gamecontroller")
                    }
                
                // Switcher settings
                switcherTab()
                    .tabItem {
                        Label("導播切換機", systemImage: "rectangle.3.group")
                    }
                
                // YouTube settings
                youtubeTab()
                    .tabItem {
                        Label("YouTube 直播", systemImage: "play.rectangle")
                    }
            }
            .padding(.horizontal, 16)
            
            Divider()
            
            // Bottom Action Bar
            HStack(spacing: 14) {
                Spacer()
                Button("取消") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                .controlSize(.regular)
                
                Button("儲存變更") {
                    localCam1.controlPort = Int(cam1ControlPortStr) ?? 52381
                    localCam1.rtspPort = Int(cam1RtspPortStr) ?? 554
                    localCam2.controlPort = Int(cam2ControlPortStr) ?? 52381
                    localCam2.rtspPort = Int(cam2RtspPortStr) ?? 554
                    
                    let counter = PeopleCounterService.shared
                    counter.currentEngineMode = selectedAiEngine
                    counter.confidenceThreshold = confidenceThresh
                    counter.minObjectSize = minObjSize
                    counter.samplingFps = fpsVal
                    counter.trackingAlpha = alphaVal
                    counter.maxMotionDistance = distVal
                    counter.isReIdEnabled = isReIdOn
                    counter.reIdSimilarity = reIdSimVal
                    counter.saveCurrentSettings()
                    
                    cam1Config = localCam1
                    cam2Config = localCam2
                    CameraRepository.shared.saveConfig(index: 1, config: localCam1)
                    CameraRepository.shared.saveConfig(index: 2, config: localCam2)
                    
                    var appSettings = CameraRepository.shared.getAppSettings()
                    appSettings.expoStrength = expoStrength
                    appSettings.switcherIp = switcherIp
                    appSettings.switcherLayoutMode = switcherLayoutMode
                    appSettings.youtubeChannelId = youtubeChannelId
                    appSettings.youtubeStreamKey = youtubeStreamKey
                    CameraRepository.shared.saveAppSettings(appSettings)
                    onSave()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 720, height: 580)
    }
    
    private func aiEngineTab() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Card 1: Re-ID 人員特徵記憶重識別 (NEW)
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: "person.line.dotted.person.fill")
                            .foregroundColor(.blue)
                        Text("Re-ID 人員特徵記憶重識別 (跨畫面與離場記憶)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.primary)
                        Spacer()
                        
                        Toggle("", isOn: $isReIdOn)
                            .toggleStyle(.switch)
                    }
                    
                    if isReIdOn {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Re-ID 視覺特徵比對嚴格度:")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                    
                                    Text("\(Int(reIdSimVal * 100))% 相似度")
                                        .font(.system(size: 12, design: .monospaced))
                                        .fontWeight(.bold)
                                        .foregroundColor(.blue)
                                }
                                
                                HStack(spacing: 12) {
                                    Text("寬鬆 (70%)")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    
                                    Slider(value: $reIdSimVal, in: 0.70...0.95, step: 0.02)
                                    
                                    Text("高精度 (95%)")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise.circle.fill")
                                    .foregroundColor(.blue)
                                Text("重啟記憶規則：App 重新啟動或切換開關時，記憶庫會自動歸零並重新計數。")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            
                            Text("💡 提示：開啟此功能後，當講員走離鏡頭後再返回畫面時，系統會自動提取其 512 維度特徵向量比對，識別為同一人並維持原 ID 編號！")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
                
                // Card 2: AI 辨識引擎模式切換
                VStack(alignment: .leading, spacing: 12) {
                    Text("AI 人體辨識與追蹤引擎模式")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("預設辨識引擎:")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        Picker("", selection: $selectedAiEngine) {
                            ForEach(AiEngineMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        
                        if selectedAiEngine == .appleVision {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(.green)
                                Text("Apple Vision 原生引擎：使用系統內建 Vision 360° 骨架神經網路，零 CPU/GPU 負擔。")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 2)
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "bolt.horizontal.circle.fill")
                                    .foregroundColor(.orange)
                                Text("CoreML YOLO 深度學習引擎：透過 Apple Neural Engine (NPU) 直通神經網路，提供 99.5%+ 抗遮擋辨識率。")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 2)
                        }
                    }
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
                
                // Card 3: 高速動態跟隨與採樣頻率
                VStack(alignment: .leading, spacing: 14) {
                    Text("高速動態跟隨與採樣頻率 (解決快速移動跟不上問題)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 14) {
                        // 1. 採樣頻率 FPS
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("AI 採樣頻率 (FPS):")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Text("\(fpsVal) FPS (\(1000/fpsVal)ms / 幀)")
                                    .font(.system(size: 12, design: .monospaced))
                                    .fontWeight(.bold)
                                    .foregroundColor(fpsVal >= 10 ? .green : .primary)
                            }
                            
                            Picker("", selection: $fpsVal) {
                                Text("6 FPS (166ms)").tag(6)
                                Text("8 FPS (125ms)").tag(8)
                                Text("10 FPS (100ms 高速)").tag(10)
                                Text("12 FPS (83ms 極速)").tag(12)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                        
                        Divider()
                        
                        // 2. 跟隨響應權重 Alpha
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("跟隨即時響應權重 (Alpha):")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Text("\(Int(alphaVal * 100))%")
                                    .font(.system(size: 12, design: .monospaced))
                                    .fontWeight(.bold)
                                    .foregroundColor(alphaVal >= 0.85 ? .green : .primary)
                            }
                            
                            HStack(spacing: 12) {
                                Text("柔和平滑")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                
                                Slider(value: $alphaVal, in: 0.60...0.98, step: 0.05)
                                
                                Text("⚡ 即時貼合 (90%)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(alphaVal >= 0.85 ? .green : .secondary)
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
                
                // Card 4: 遠距離與小目標辨識靈敏度
                VStack(alignment: .leading, spacing: 14) {
                    Text("遠距離與小目標辨識靈敏度控制 (捕捉遠端坐姿人員)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 14) {
                        // Slider: 辨識信心門檻 (Confidence Threshold)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("辨識靈敏度門檻 (Confidence):")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Text("\(String(format: "%.2f", confidenceThresh))")
                                    .font(.system(size: 12, design: .monospaced))
                                    .fontWeight(.bold)
                                    .foregroundColor(confidenceThresh <= 0.10 ? .green : .primary)
                            }
                            
                            HStack(spacing: 12) {
                                Text("⚡ 超高靈敏 (0.06 抓遠端)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(confidenceThresh <= 0.10 ? .green : .secondary)
                                
                                Slider(value: $confidenceThresh, in: 0.04...0.30, step: 0.01)
                                
                                Text("高過濾 (0.30)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
            }
            .padding(16)
        }
    }
    
    private func cameraTab(title: String, config: Binding<CameraConfig>, controlPortStr: Binding<String>, rtspPortStr: Binding<String>) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Section 1: 基本相機資訊
                VStack(alignment: .leading, spacing: 10) {
                    Text("基本相機資訊")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 10) {
                        HStack {
                            Text("相機名稱:")
                                .font(.system(size: 12))
                                .frame(width: 110, alignment: .trailing)
                            TextField("例如：CAM 01", text: config.camName)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        HStack {
                            Text("IP 位址:")
                                .font(.system(size: 12))
                                .frame(width: 110, alignment: .trailing)
                            TextField("例如：192.168.5.153", text: config.ipAddress)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                .padding(14)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
                
                // Section 2: 通訊埠與 RTSP 碼流設定
                VStack(alignment: .leading, spacing: 10) {
                    Text("通訊埠與 RTSP 碼流設定")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 10) {
                        HStack {
                            Text("VISCA 控制埠:")
                                .font(.system(size: 12))
                                .frame(width: 110, alignment: .trailing)
                            
                            TextField("52381", text: controlPortStr)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                            
                            Toggle("主畫面顯示 Port", isOn: config.showPort)
                                .toggleStyle(.checkbox)
                                .padding(.leading, 8)
                            
                            Spacer()
                        }
                        
                        HStack {
                            Text("RTSP 串流埠:")
                                .font(.system(size: 12))
                                .frame(width: 110, alignment: .trailing)
                            
                            TextField("554", text: rtspPortStr)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                            
                            Text("RTSP 路徑:")
                                .font(.system(size: 12))
                                .padding(.leading, 12)
                            
                            TextField("live/av1", text: config.rtspPath)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        HStack {
                            Text("快速選擇碼流:")
                                .font(.system(size: 12))
                                .frame(width: 110, alignment: .trailing)
                            
                            HStack(spacing: 10) {
                                if config.rtspPath.wrappedValue == "live/av1" {
                                    Button(action: { config.rtspPath.wrappedValue = "live/av1" }) {
                                        Label("高清主碼流 (live/av1)", systemImage: "video.fill")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                } else {
                                    Button(action: { config.rtspPath.wrappedValue = "live/av1" }) {
                                        Label("高清主碼流 (live/av1)", systemImage: "video.fill")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                                
                                if config.rtspPath.wrappedValue == "live/av2" {
                                    Button(action: { config.rtspPath.wrappedValue = "live/av2" }) {
                                        Label("零延遲子碼流 (live/av2)", systemImage: "bolt.fill")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                } else {
                                    Button(action: { config.rtspPath.wrappedValue = "live/av2" }) {
                                        Label("零延遲子碼流 (live/av2)", systemImage: "bolt.fill")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            
                            Spacer()
                        }
                    }
                }
                .padding(14)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
                
                // Section 3: 串流認證與通訊協定
                VStack(alignment: .leading, spacing: 10) {
                    Text("串流認證與控制協定")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 10) {
                        HStack {
                            Text("串流帳號:")
                                .font(.system(size: 12))
                                .frame(width: 110, alignment: .trailing)
                            TextField("admin", text: config.account)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        HStack {
                            Text("串流密碼:")
                                .font(.system(size: 12))
                                .frame(width: 110, alignment: .trailing)
                            SecureField("•••••", text: config.password)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        HStack {
                            Text("控制協定:")
                                .font(.system(size: 12))
                                .frame(width: 110, alignment: .trailing)
                            
                            Picker("", selection: config.protocolType) {
                                Text("VISCA / UDP").tag("VISCA/UDP")
                                Text("VISCA / TCP").tag("VISCA/TCP")
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 220)
                            
                            Spacer()
                        }
                    }
                }
                .padding(14)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
            }
            .padding(16)
        }
    }
    
    private func joystickTab() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("硬體控制器狀態")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    Image(systemName: JoystickManager.shared.isControllerConnected ? "gamecontroller.fill" : "gamecontroller")
                        .font(.system(size: 18))
                        .foregroundColor(JoystickManager.shared.isControllerConnected ? .green : .secondary)
                    
                    Text("目前的硬體控制器:")
                        .font(.system(size: 12))
                    
                    Text(JoystickManager.shared.isControllerConnected ? JoystickManager.shared.controllerName : "未偵測到實體搖桿")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(JoystickManager.shared.isControllerConnected ? .green : .red)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
            
            VStack(alignment: .leading, spacing: 12) {
                Text("搖桿靈敏度指數曲線 (Expo Curve)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                
                Slider(value: $expoStrength, in: 1.0...3.0, step: 0.1) {
                    Text("Expo 強度: \(String(format: "%.1f", expoStrength))")
                        .font(.system(size: 12, weight: .bold))
                } minimumValueLabel: {
                    Text("1.0 (線性)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } maximumValueLabel: {
                    Text("3.0 (高微調對比)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Text("💡 提示：調整 Expo 曲線能讓實體搖桿在微推時極度細緻精準，同時保持全推時的最大轉動速度。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
            
            Spacer()
        }
        .padding(16)
    }
    
    private func switcherTab() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section 1: 導播排版模式偏好
            VStack(alignment: .leading, spacing: 12) {
                Text("導播排版顯示模式 (Switcher Layout)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                
                HStack(alignment: .top, spacing: 12) {
                    Text("預設排版模式:")
                        .font(.system(size: 12))
                        .frame(width: 120, alignment: .trailing)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("", selection: $switcherLayoutMode) {
                            ForEach(SwitcherLayoutMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("• 底部廣播控制台：雙機全幅置頂，下方展開完整雙母線廣播控制台 (推薦)")
                            Text("• 右側直立導播欄：上方三欄佈局 (CAM 1 + CAM 2 + 直立導播控制欄)")
                            Text("• 獨立懸浮導播窗：雙機畫面不受干擾，導播面板以獨立浮動視窗彈出 (支援雙螢幕)")
                            Text("• 單槽子母預覽：保留原插槽切換，導播控制面板頂部自動嵌入即時 16:9 相機畫面")
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                    }
                }
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
            
            // Section 2: 導播機 IP 設定
            VStack(alignment: .leading, spacing: 12) {
                Text("導播切換機連線設定")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                
                HStack {
                    Text("導播機 IP 位址:")
                        .font(.system(size: 12))
                        .frame(width: 120, alignment: .trailing)
                    TextField("例如：192.168.5.99", text: $switcherIp)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }
                
                Text("💡 提示：支援 RGBLink Mini Edge / Mini Pro 或具備 Open API / Web 控制的導播切換器。主畫面與浮動視窗均可一鍵連線。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
            
            Spacer()
        }
        .padding(16)
    }
    
    @ObservedObject private var ytService = YouTubeLiveService.shared

    private func youtubeTab() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Google Cloud Console OAuth 2.0 API 認證設定")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                
                VStack(spacing: 10) {
                    HStack {
                        Text("Google Client ID:")
                            .font(.system(size: 12))
                            .frame(width: 140, alignment: .trailing)
                        TextField("例如：xxxx.apps.googleusercontent.com", text: $ytService.clientID)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack {
                        Text("Google Client Secret:")
                            .font(.system(size: 12))
                            .frame(width: 140, alignment: .trailing)
                        SecureField("GOCSPX-xxxxxx", text: $ytService.clientSecret)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                
                HStack(spacing: 12) {
                    Button("儲存 OAuth 憑證") {
                        ytService.saveClientCredentials(id: ytService.clientID, secret: ytService.clientSecret)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    
                    if ytService.isLoggedIn {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("已成功連線頻道：\(ytService.channelTitle)")
                                .font(.system(size: 11, weight: .bold))
                        }
                    } else {
                        Button("🔑 觸發 Google OAuth 2.0 登入") {
                            ytService.saveClientCredentials(id: ytService.clientID, secret: ytService.clientSecret)
                            ytService.startOAuthLogin { _, _ in }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.top, 4)
                
                Text("💡 提示：輸入 Google Cloud Console 產生的 Client ID 與 Secret 後點擊儲存，更新 App 時憑證將自動保留於 macOS Keychain (系統金鑰圈)，完全不需要重新登入！")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
            
            Spacer()
        }
        .padding(16)
    }
}
