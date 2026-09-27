import SwiftUI

enum SwitcherLayoutStyle {
    case standard
    case bottomConsole
    case rightSidebar
    case embedded(cameraIndex: Int)
    case floating
}

struct SwitcherControlView: View {
    var layoutStyle: SwitcherLayoutStyle = .standard
    @Binding var isAiLiveEnabled: Bool
    
    @ObservedObject private var client = RGBLinkClient.shared
    @State private var currentIp: String = CameraRepository.shared.getSwitcherIp()
    
    init(layoutStyle: SwitcherLayoutStyle = .standard, isAiLiveEnabled: Binding<Bool> = .constant(true)) {
        self.layoutStyle = layoutStyle
        self._isAiLiveEnabled = isAiLiveEnabled
    }
    
    let sources = ["CAM 1", "CAM 2", "CAM 3", "CAM 4"]
    let effects = [
        "CUT", "FADE", "<-[]->", "L->R", "T->B", "LT->RB", "<-+->",
        "R->L", "B->T", "L<-M->R", "T<-M->B", "->+<-", "|||->", "->[]<-", "<-O->"
    ]
    
    var body: some View {
        Group {
            switch layoutStyle {
            case .bottomConsole:
                bottomConsoleLayout
            case .rightSidebar:
                rightSidebarLayout
            case .embedded(let camIdx):
                embeddedLayout(cameraIndex: camIdx)
            case .floating:
                floatingLayout
            case .standard:
                standardLayout
            }
        }
        .onAppear {
            self.currentIp = CameraRepository.shared.getSwitcherIp()
            client.switcherIp = self.currentIp
            client.connect()
        }
    }
    
    // MARK: - Connection Header
    private var connectionHeader: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(client.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(client.isConnected ? "導播機已連線 (\(client.switcherIp))" : "導播機未連線")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 6) {
                TextField("IP:", text: $currentIp)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
                    .onChange(of: currentIp) { newValue in
                        client.switcherIp = newValue
                        CameraRepository.shared.setSwitcherIp(newValue)
                    }
                
                Button(client.isConnected ? "中斷" : "連線") {
                    if client.isConnected {
                        client.disconnect()
                    } else {
                        client.connect()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
    
    // MARK: - 1. Bottom Broadcast Console Layout (底部廣播主控台)
    private var bottomConsoleLayout: some View {
        VStack(spacing: 8) {
            connectionHeader
                .padding(.horizontal, 10)
                .padding(.top, 4)
            
            Divider()
            
            HStack(alignment: .top, spacing: 16) {
                // Left: Program & Preview Busses
                VStack(spacing: 8) {
                    SwitcherBusRow(
                        title: "PROGRAM",
                        color: .red,
                        sources: sources,
                        activeSource: client.pgmSource,
                        titleWidth: 85,
                        onSelect: { client.setPgmSource($0) }
                    )
                    SwitcherBusRow(
                        title: "PREVIEW",
                        color: .green,
                        sources: sources,
                        activeSource: client.pstSource,
                        titleWidth: 85,
                        onSelect: { client.setPstSource($0) }
                    )
                }
                .frame(maxWidth: .infinity)
                
                Divider()
                
                // Middle: Transition
                SwitcherTransitionControl(
                    effects: effects,
                    currentEffect: client.switchEffect,
                    onCut: { client.sendCut() },
                    onAuto: { client.sendAuto() },
                    onSelectEffect: { client.setTransitionEffect($0) }
                )
                .frame(width: 175)
                
                Divider()
                
                // Right: PIP Control
                SwitcherPipControl(
                    pipMode: client.pipMode,
                    onTogglePip: { client.setPipMode(client.pipMode == 0 ? 2 : 0) },
                    onSelectPosition: { client.setPipMode($0) }
                )
                .frame(width: 195)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
        .padding(8)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.92))
    }
    
    // MARK: - 2. Right Sidebar Layout (右側直立導播欄)
    private var rightSidebarLayout: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Circle()
                    .fill(client.isConnected ? Color.green : Color.red)
                    .frame(width: 7, height: 7)
                Text(client.isConnected ? "導播機已連線" : "導播機未連線")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(client.isConnected ? .green : .red)
                Spacer()
                Button(client.isConnected ? "中斷" : "連線") {
                    if client.isConnected {
                        client.disconnect()
                    } else {
                        client.connect()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            .padding(.horizontal, 6)
            
            Divider()
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    SwitcherBusGrid(
                        title: "PROGRAM (目前輸出)",
                        color: .red,
                        sources: sources,
                        activeSource: client.pgmSource,
                        onSelect: { client.setPgmSource($0) }
                    )
                    
                    SwitcherBusGrid(
                        title: "PREVIEW (預監)",
                        color: .green,
                        sources: sources,
                        activeSource: client.pstSource,
                        onSelect: { client.setPstSource($0) }
                    )
                    
                    Divider()
                    
                    SwitcherTransitionControl(
                        effects: effects,
                        currentEffect: client.switchEffect,
                        isCompact: true,
                        onCut: { client.sendCut() },
                        onAuto: { client.sendAuto() },
                        onSelectEffect: { client.setTransitionEffect($0) }
                    )
                    
                    Divider()
                    
                    SwitcherPipControl(
                        pipMode: client.pipMode,
                        isCompact: true,
                        onTogglePip: { client.setPipMode(client.pipMode == 0 ? 2 : 0) },
                        onSelectPosition: { client.setPipMode($0) }
                    )
                }
                .padding(.horizontal, 6)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
    
    // MARK: - 3. Embedded Slot Layout (單槽子母預覽)
    private func embeddedLayout(cameraIndex: Int) -> some View {
        let camConfig = CameraRepository.shared.getConfig(index: cameraIndex)
        let isPgm = (client.pgmSource == (cameraIndex - 1))
        let isPst = (client.pstSource == (cameraIndex - 1))
        let tallyColor: Color = isPgm ? .red : (isPst ? .green : Color.secondary.opacity(0.3))
        let tallyLineWidth: CGFloat = (isPgm || isPst) ? 3.0 : 1.0
        
        return VStack(spacing: 8) {
            // Live Embedded Camera Preview
            ZStack(alignment: .topTrailing) {
                PlayerView(rtspUrl: camConfig.rtspUrl, index: cameraIndex, isAiEnabled: $isAiLiveEnabled)
                    .id(camConfig.rtspUrl)
                    .aspectRatio(16/9, contentMode: .fit)
                    .background(Color.black)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(tallyColor, lineWidth: tallyLineWidth)
                    )
                
                // Mini Tally Tag
                HStack(spacing: 4) {
                    if isPgm {
                        Text("🔴 ON AIR")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .cornerRadius(3)
                    } else if isPst {
                        Text("🟢 PREVIEW")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .cornerRadius(3)
                    }
                }
                .padding(4)
            }
            .frame(maxHeight: 180)
            
            Divider()
            
            // Compact Switcher Controls beneath video
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    SwitcherBusRow(
                        title: "PGM",
                        color: .red,
                        sources: sources,
                        activeSource: client.pgmSource,
                        buttonHeight: 26,
                        titleWidth: 35,
                        onSelect: { client.setPgmSource($0) }
                    )
                    
                    SwitcherBusRow(
                        title: "PST",
                        color: .green,
                        sources: sources,
                        activeSource: client.pstSource,
                        buttonHeight: 26,
                        titleWidth: 35,
                        onSelect: { client.setPstSource($0) }
                    )
                    
                    HStack(spacing: 8) {
                        Button(action: { client.sendCut() }) {
                            Text("CUT")
                                .font(.system(size: 10, weight: .black))
                                .frame(maxWidth: .infinity, minHeight: 26)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        
                        Button(action: { client.sendAuto() }) {
                            Text("AUTO")
                                .font(.system(size: 10, weight: .black))
                                .frame(maxWidth: .infinity, minHeight: 26)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        
                        Menu {
                            ForEach(0..<effects.count, id: \.self) { idx in
                                Button(effects[idx]) { client.setTransitionEffect(idx) }
                            }
                        } label: {
                            Text("特效")
                                .font(.system(size: 10))
                        }
                        .frame(width: 55, height: 26)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(6)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.85))
    }
    
    // MARK: - 4. Floating Window Layout (獨立懸浮窗)
    private var floatingLayout: some View {
        VStack(spacing: 12) {
            connectionHeader
            Divider()
            
            SwitcherBusRow(
                title: "PROGRAM (輸出)",
                color: .red,
                sources: sources,
                activeSource: client.pgmSource,
                buttonHeight: 38,
                titleWidth: 110,
                onSelect: { client.setPgmSource($0) }
            )
            
            SwitcherBusRow(
                title: "PREVIEW (預監)",
                color: .green,
                sources: sources,
                activeSource: client.pstSource,
                buttonHeight: 38,
                titleWidth: 110,
                onSelect: { client.setPstSource($0) }
            )
            
            Divider()
            
            HStack(spacing: 16) {
                SwitcherTransitionControl(
                    effects: effects,
                    currentEffect: client.switchEffect,
                    onCut: { client.sendCut() },
                    onAuto: { client.sendAuto() },
                    onSelectEffect: { client.setTransitionEffect($0) }
                )
                
                Divider()
                
                SwitcherPipControl(
                    pipMode: client.pipMode,
                    onTogglePip: { client.setPipMode(client.pipMode == 0 ? 2 : 0) },
                    onSelectPosition: { client.setPipMode($0) }
                )
            }
        }
        .padding(14)
        .frame(minWidth: 500, minHeight: 320)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - 5. Standard Layout (Classic)
    private var standardLayout: some View {
        VStack(spacing: 8) {
            connectionHeader
                .padding(.horizontal, 8)
                .padding(.top, 4)
            
            Divider()
            
            VStack(spacing: 8) {
                SwitcherBusRow(
                    title: "PROGRAM",
                    color: .red,
                    sources: sources,
                    activeSource: client.pgmSource,
                    titleWidth: 70,
                    onSelect: { client.setPgmSource($0) }
                )
                SwitcherBusRow(
                    title: "PREVIEW",
                    color: .green,
                    sources: sources,
                    activeSource: client.pstSource,
                    titleWidth: 70,
                    onSelect: { client.setPstSource($0) }
                )
            }
            .padding(.horizontal, 8)
            
            Divider()
            
            HStack(spacing: 16) {
                SwitcherTransitionControl(
                    effects: effects,
                    currentEffect: client.switchEffect,
                    onCut: { client.sendCut() },
                    onAuto: { client.sendAuto() },
                    onSelectEffect: { client.setTransitionEffect($0) }
                )
                .frame(maxWidth: .infinity)
                
                SwitcherPipControl(
                    pipMode: client.pipMode,
                    onTogglePip: { client.setPipMode(client.pipMode == 0 ? 2 : 0) },
                    onSelectPosition: { client.setPipMode($0) }
                )
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
        .padding(8)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
    }
}

// MARK: - Internal Reusable Subviews (內部專用子組件，避免檔案零碎化)

private struct SwitcherBusRow: View {
    let title: String
    let color: Color
    let sources: [String]
    let activeSource: Int
    var buttonHeight: CGFloat = 34
    var titleWidth: CGFloat = 85
    let onSelect: (Int) -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(color)
            }
            .frame(width: titleWidth, alignment: .leading)
            
            ForEach(0..<sources.count, id: \.self) { i in
                Button(action: { onSelect(i) }) {
                    Text(sources[i])
                        .font(.system(size: 11, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: buttonHeight)
                }
                .buttonStyle(BusButtonStyle(isActive: activeSource == i, activeColor: color))
            }
        }
    }
}

private struct SwitcherBusGrid: View {
    let title: String
    let color: Color
    let sources: [String]
    let activeSource: Int
    let onSelect: (Int) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(color)
            }
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(0..<sources.count, id: \.self) { i in
                    Button(action: { onSelect(i) }) {
                        Text(sources[i])
                            .font(.system(size: 11, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(BusButtonStyle(isActive: activeSource == i, activeColor: color))
                }
            }
        }
    }
}

private struct SwitcherTransitionControl: View {
    let effects: [String]
    let currentEffect: Int
    var isCompact: Bool = false
    let onCut: () -> Void
    let onAuto: () -> Void
    let onSelectEffect: (Int) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 4 : 6) {
            Text("轉場控制 (Transition)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
            
            HStack(spacing: isCompact ? 6 : 8) {
                Button(action: onCut) {
                    Text("CUT")
                        .font(.system(size: isCompact ? 11 : 12, weight: .black))
                        .frame(maxWidth: .infinity, minHeight: isCompact ? 28 : 32)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                
                Button(action: onAuto) {
                    Text("AUTO")
                        .font(.system(size: isCompact ? 11 : 12, weight: .black))
                        .frame(maxWidth: .infinity, minHeight: isCompact ? 28 : 32)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            
            Menu {
                ForEach(0..<effects.count, id: \.self) { idx in
                    Button(effects[idx]) { onSelectEffect(idx) }
                }
            } label: {
                HStack {
                    Text("特效: \(effects[currentEffect < effects.count ? currentEffect : 0])")
                        .font(.system(size: isCompact ? 10 : 11))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                }
                .padding(.horizontal, isCompact ? 4 : 6)
                .frame(height: isCompact ? 20 : 24)
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct SwitcherPipControl: View {
    let pipMode: Int
    var isCompact: Bool = false
    let onTogglePip: () -> Void
    let onSelectPosition: (Int) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 4 : 6) {
            Text("子母畫面 (PIP Control)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
            
            Button(action: onTogglePip) {
                HStack {
                    Image(systemName: pipMode == 0 ? "rectangle.inset.topright.fill" : "xmark.circle")
                    Text(pipMode == 0 ? "開啟 PIP 疊層" : "關閉 PIP 疊層")
                }
                .font(.system(size: isCompact ? 10 : 11, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: isCompact ? 24 : 28)
            }
            .buttonStyle(.bordered)
            
            Picker("", selection: Binding(
                get: { pipMode == 0 ? 0 : pipMode },
                set: { onSelectPosition($0) }
            )) {
                Text("無").tag(0)
                Text("左上").tag(2)
                Text("右上").tag(3)
                Text("左下").tag(4)
                Text("右下").tag(5)
            }
            .pickerStyle(.segmented)
            .controlSize(isCompact ? .mini : .small)
            .disabled(pipMode == 0)
        }
    }
}

struct BusButtonStyle: ButtonStyle {
    var isActive: Bool
    var activeColor: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(isActive ? activeColor : Color.gray.opacity(0.15))
            .foregroundColor(isActive ? .white : .primary)
            .cornerRadius(6)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.1), value: isActive)
    }
}
