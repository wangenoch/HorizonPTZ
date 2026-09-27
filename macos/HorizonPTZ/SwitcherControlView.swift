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
                    // PGM Bus
                    HStack(spacing: 10) {
                        HStack(spacing: 4) {
                            Circle().fill(Color.red).frame(width: 8, height: 8)
                            Text("PROGRAM")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.red)
                        }
                        .frame(width: 90, alignment: .leading)
                        
                        ForEach(0..<4, id: \.self) { i in
                            Button(action: { client.setPgmSource(i) }) {
                                Text(sources[i])
                                    .font(.system(size: 12, weight: .bold))
                                    .frame(maxWidth: .infinity, minHeight: 34)
                            }
                            .buttonStyle(BusButtonStyle(isActive: client.pgmSource == i, activeColor: .red))
                        }
                    }
                    
                    // PST Bus
                    HStack(spacing: 10) {
                        HStack(spacing: 4) {
                            Circle().fill(Color.green).frame(width: 8, height: 8)
                            Text("PREVIEW")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.green)
                        }
                        .frame(width: 90, alignment: .leading)
                        
                        ForEach(0..<4, id: \.self) { i in
                            Button(action: { client.setPstSource(i) }) {
                                Text(sources[i])
                                    .font(.system(size: 12, weight: .bold))
                                    .frame(maxWidth: .infinity, minHeight: 34)
                            }
                            .buttonStyle(BusButtonStyle(isActive: client.pstSource == i, activeColor: .green))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                
                Divider()
                
                // Middle: Transition
                VStack(alignment: .leading, spacing: 6) {
                    Text("轉場控制 (Transition)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        Button(action: { client.sendCut() }) {
                            Text("CUT")
                                .font(.system(size: 12, weight: .black))
                                .frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        
                        Button(action: { client.sendAuto() }) {
                            Text("AUTO")
                                .font(.system(size: 12, weight: .black))
                                .frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                    
                    Menu {
                        ForEach(0..<effects.count, id: \.self) { idx in
                            Button(effects[idx]) {
                                client.setTransitionEffect(idx)
                            }
                        }
                    } label: {
                        HStack {
                            Text("特效: \(effects[client.switchEffect < effects.count ? client.switchEffect : 0])")
                                .font(.system(size: 11))
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9))
                        }
                        .padding(.horizontal, 6)
                        .frame(height: 22)
                    }
                    .buttonStyle(.bordered)
                }
                .frame(width: 175)
                
                Divider()
                
                // Right: PIP Control
                VStack(alignment: .leading, spacing: 6) {
                    Text("子母畫面 (PIP Control)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        client.setPipMode(client.pipMode == 0 ? 2 : 0)
                    }) {
                        HStack {
                            Image(systemName: client.pipMode == 0 ? "rectangle.inset.topright.fill" : "xmark.circle")
                            Text(client.pipMode == 0 ? "開啟 PIP 疊層" : "關閉 PIP 疊層")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .buttonStyle(.bordered)
                    
                    Picker("", selection: Binding(
                        get: { client.pipMode == 0 ? 0 : client.pipMode },
                        set: { client.setPipMode($0) }
                    )) {
                        Text("無").tag(0)
                        Text("左上").tag(2)
                        Text("右上").tag(3)
                        Text("左下").tag(4)
                        Text("右下").tag(5)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .disabled(client.pipMode == 0)
                }
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
                    // PGM (2x2 Grid)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Circle().fill(Color.red).frame(width: 6, height: 6)
                            Text("PROGRAM (目前輸出)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.red)
                        }
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                            ForEach(0..<4, id: \.self) { i in
                                Button(action: { client.setPgmSource(i) }) {
                                    Text(sources[i])
                                        .font(.system(size: 11, weight: .bold))
                                        .frame(maxWidth: .infinity, minHeight: 30)
                                }
                                .buttonStyle(BusButtonStyle(isActive: client.pgmSource == i, activeColor: .red))
                            }
                        }
                    }
                    
                    // PST (2x2 Grid)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Circle().fill(Color.green).frame(width: 6, height: 6)
                            Text("PREVIEW (預監)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.green)
                        }
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                            ForEach(0..<4, id: \.self) { i in
                                Button(action: { client.setPstSource(i) }) {
                                    Text(sources[i])
                                        .font(.system(size: 11, weight: .bold))
                                        .frame(maxWidth: .infinity, minHeight: 30)
                                }
                                .buttonStyle(BusButtonStyle(isActive: client.pstSource == i, activeColor: .green))
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Transition
                    VStack(alignment: .leading, spacing: 4) {
                        Text("轉場 (Transition)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 6) {
                            Button(action: { client.sendCut() }) {
                                Text("CUT")
                                    .font(.system(size: 11, weight: .black))
                                    .frame(maxWidth: .infinity, minHeight: 28)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            
                            Button(action: { client.sendAuto() }) {
                                Text("AUTO")
                                    .font(.system(size: 11, weight: .black))
                                    .frame(maxWidth: .infinity, minHeight: 28)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                        }
                        
                        Menu {
                            ForEach(0..<effects.count, id: \.self) { idx in
                                Button(effects[idx]) {
                                    client.setTransitionEffect(idx)
                                }
                            }
                        } label: {
                            HStack {
                                Text("特效: \(effects[client.switchEffect < effects.count ? client.switchEffect : 0])")
                                    .font(.system(size: 10))
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 8))
                            }
                            .frame(height: 20)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Divider()
                    
                    // PIP
                    VStack(alignment: .leading, spacing: 4) {
                        Text("子母畫面 (PIP)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        Button(action: {
                            client.setPipMode(client.pipMode == 0 ? 2 : 0)
                        }) {
                            Text(client.pipMode == 0 ? "開啟 PIP" : "關閉 PIP")
                                .font(.system(size: 10, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 24)
                        }
                        .buttonStyle(.bordered)
                        
                        Picker("", selection: Binding(
                            get: { client.pipMode == 0 ? 0 : client.pipMode },
                            set: { client.setPipMode($0) }
                        )) {
                            Text("無").tag(0)
                            Text("左上").tag(2)
                            Text("右上").tag(3)
                            Text("左下").tag(4)
                            Text("右下").tag(5)
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.mini)
                        .disabled(client.pipMode == 0)
                    }
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
                    // PGM & PST
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PGM").font(.system(size: 9, weight: .bold)).foregroundColor(.red)
                            HStack(spacing: 4) {
                                ForEach(0..<4, id: \.self) { i in
                                    Button(action: { client.setPgmSource(i) }) {
                                        Text(sources[i])
                                            .font(.system(size: 10, weight: .bold))
                                            .frame(maxWidth: .infinity, minHeight: 26)
                                    }
                                    .buttonStyle(BusButtonStyle(isActive: client.pgmSource == i, activeColor: .red))
                                }
                            }
                        }
                    }
                    
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PST").font(.system(size: 9, weight: .bold)).foregroundColor(.green)
                            HStack(spacing: 4) {
                                ForEach(0..<4, id: \.self) { i in
                                    Button(action: { client.setPstSource(i) }) {
                                        Text(sources[i])
                                            .font(.system(size: 10, weight: .bold))
                                            .frame(maxWidth: .infinity, minHeight: 26)
                                    }
                                    .buttonStyle(BusButtonStyle(isActive: client.pstSource == i, activeColor: .green))
                                }
                            }
                        }
                    }
                    
                    // Transition Quick Bar
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
            
            // Program Bus
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    Text("PROGRAM (目前輸出 - 直播中)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.red)
                }
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { i in
                        Button(action: { client.setPgmSource(i) }) {
                            Text(sources[i])
                                .font(.system(size: 13, weight: .bold))
                                .frame(maxWidth: .infinity, minHeight: 38)
                        }
                        .buttonStyle(BusButtonStyle(isActive: client.pgmSource == i, activeColor: .red))
                    }
                }
            }
            
            // Preview Bus
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                    Text("PREVIEW (預監準備)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.green)
                }
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { i in
                        Button(action: { client.setPstSource(i) }) {
                            Text(sources[i])
                                .font(.system(size: 13, weight: .bold))
                                .frame(maxWidth: .infinity, minHeight: 38)
                        }
                        .buttonStyle(BusButtonStyle(isActive: client.pstSource == i, activeColor: .green))
                    }
                }
            }
            
            Divider()
            
            // Transition & PIP
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("轉場控制 (Transition)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        Button(action: { client.sendCut() }) {
                            Text("CUT")
                                .font(.system(size: 12, weight: .black))
                                .frame(maxWidth: .infinity, minHeight: 34)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        
                        Button(action: { client.sendAuto() }) {
                            Text("AUTO")
                                .font(.system(size: 12, weight: .black))
                                .frame(maxWidth: .infinity, minHeight: 34)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                    
                    Menu {
                        ForEach(0..<effects.count, id: \.self) { idx in
                            Button(effects[idx]) { client.setTransitionEffect(idx) }
                        }
                    } label: {
                        HStack {
                            Text("轉場特效: \(effects[client.switchEffect < effects.count ? client.switchEffect : 0])")
                                .font(.system(size: 11))
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                        }
                        .frame(height: 24)
                    }
                    .buttonStyle(.bordered)
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("子母畫面 (PIP Control)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        client.setPipMode(client.pipMode == 0 ? 2 : 0)
                    }) {
                        Text(client.pipMode == 0 ? "開啟 PIP" : "關閉 PIP")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.bordered)
                    
                    Picker("", selection: Binding(
                        get: { client.pipMode == 0 ? 0 : client.pipMode },
                        set: { client.setPipMode($0) }
                    )) {
                        Text("無").tag(0)
                        Text("左上").tag(2)
                        Text("右上").tag(3)
                        Text("左下").tag(4)
                        Text("右下").tag(5)
                    }
                    .pickerStyle(.segmented)
                    .disabled(client.pipMode == 0)
                }
            }
        }
        .padding(14)
        .frame(minWidth: 500, minHeight: 320)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Standard Layout (Classic)
    private var standardLayout: some View {
        VStack(spacing: 8) {
            connectionHeader
                .padding(.horizontal, 8)
                .padding(.top, 4)
            
            Divider()
            
            VStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("PROGRAM (目前輸出)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.red)
                    HStack(spacing: 8) {
                        ForEach(0..<4, id: \.self) { i in
                            Button(action: { client.setPgmSource(i) }) {
                                Text(sources[i])
                                    .fontWeight(.bold)
                                    .frame(maxWidth: .infinity, minHeight: 32)
                            }
                            .buttonStyle(BusButtonStyle(isActive: client.pgmSource == i, activeColor: .red))
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("PREVIEW (預監畫面)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.green)
                    HStack(spacing: 8) {
                        ForEach(0..<4, id: \.self) { i in
                            Button(action: { client.setPstSource(i) }) {
                                Text(sources[i])
                                    .fontWeight(.bold)
                                    .frame(maxWidth: .infinity, minHeight: 32)
                            }
                            .buttonStyle(BusButtonStyle(isActive: client.pstSource == i, activeColor: .green))
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            
            Divider()
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("轉場控制 (Transition)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        Button(action: { client.sendCut() }) {
                            Text("CUT")
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        
                        Button(action: { client.sendAuto() }) {
                            Text("AUTO")
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                    
                    Menu {
                        ForEach(0..<effects.count, id: \.self) { idx in
                            Button(effects[idx]) { client.setTransitionEffect(idx) }
                        }
                    } label: {
                        HStack {
                            Text("轉場特效: \(effects[client.switchEffect < effects.count ? client.switchEffect : 0])")
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("子母畫面 (PIP Control)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        client.setPipMode(client.pipMode == 0 ? 2 : 0)
                    }) {
                        Text(client.pipMode == 0 ? "開啟 PIP" : "關閉 PIP")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    
                    Picker("", selection: Binding(
                        get: { client.pipMode == 0 ? 0 : client.pipMode },
                        set: { client.setPipMode($0) }
                    )) {
                        Text("無").tag(0)
                        Text("左上").tag(2)
                        Text("右上").tag(3)
                        Text("左下").tag(4)
                        Text("右下").tag(5)
                    }
                    .pickerStyle(.segmented)
                    .disabled(client.pipMode == 0)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
        .padding(8)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
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
