import SwiftUI

struct SwitcherControlView: View {
    @ObservedObject private var client = RGBLinkClient.shared
    @State private var currentIp: String = CameraRepository.shared.getSwitcherIp()
    
    let sources = ["CAM 1", "CAM 2", "CAM 3", "CAM 4"]
    let effects = [
        "CUT", "FADE", "<-[]->", "L->R", "T->B", "LT->RB", "<-+->",
        "R->L", "B->T", "L<-M->R", "T<-M->B", "->+<-", "|||->", "->[]<-", "<-O->"
    ]
    
    var body: some View {
        VStack(spacing: 8) {
            // Connection status and Quick Connect
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(client.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(client.isConnected ? "導播機已連線 (\(client.switcherIp))" : "導播機未連線")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    TextField("IP:", text: $currentIp)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
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
            .padding(.horizontal, 8)
            .padding(.top, 4)
            
            Divider()
            
            // Switcher Bus Panels
            VStack(spacing: 8) {
                // Program Bus (PGM) - RED when active
                VStack(alignment: .leading, spacing: 3) {
                    Text("PROGRAM (目前輸出)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.red)
                    
                    HStack(spacing: 8) {
                        ForEach(0..<4, id: \.self) { i in
                            Button(action: {
                                client.setPgmSource(i)
                            }) {
                                Text(sources[i])
                                    .fontWeight(.bold)
                                    .frame(maxWidth: .infinity, minHeight: 32)
                            }
                            .buttonStyle(BusButtonStyle(isActive: client.pgmSource == i, activeColor: .red))
                        }
                    }
                }
                
                // Preview Bus (PST) - GREEN when active
                VStack(alignment: .leading, spacing: 3) {
                    Text("PREVIEW (預監畫面)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.green)
                    
                    HStack(spacing: 8) {
                        ForEach(0..<4, id: \.self) { i in
                            Button(action: {
                                client.setPstSource(i)
                            }) {
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
            
            // Transition and PIP Section
            HStack(spacing: 16) {
                // Transition controls
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
                    
                    // Transition Effect picker
                    Menu {
                        ForEach(0..<effects.count, id: \.self) { idx in
                            Button(effects[idx]) {
                                client.setTransitionEffect(idx)
                            }
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
                
                // PIP controls
                VStack(alignment: .leading, spacing: 4) {
                    Text("子母畫面 (PIP Control)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        Button(action: {
                            client.setPipMode(client.pipMode == 0 ? 2 : 0)
                        }) {
                            Text(client.pipMode == 0 ? "開啟 PIP" : "關閉 PIP")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    // PIP positions
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
        .onAppear {
            self.currentIp = CameraRepository.shared.getSwitcherIp()
            client.switcherIp = self.currentIp
            client.connect()
        }
        .onDisappear {
            client.disconnect()
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
