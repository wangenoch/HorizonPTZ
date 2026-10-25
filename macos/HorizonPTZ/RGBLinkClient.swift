import Foundation
import Network

class RGBLinkClient: ObservableObject {
    static let shared = RGBLinkClient()
    
    @Published var isConnected = false
    @Published var switcherIp: String = "192.168.5.99"
    @Published var pgmSource = -1 // 0-3 (CAM1-4), -1: 未連線或未選中
    @Published var pstSource = -1 // 0-3 (CAM1-4), -1: 未連線或未選中
    @Published var pipMode = 0 // 0: Off, 1+: On
    @Published var switchEffect = 0 // 0+: Cut, Fade, etc.
    
    private var connection: NWConnection?
    private var nextSn: UInt8 = 0
    private let queue = DispatchQueue(label: "RGBLinkClientQueue")
    
    private var lastFeedbackTime: Date? = nil
    private var checkTimer: Timer? = nil
    
    private init() {
        self.switcherIp = CameraRepository.shared.getSwitcherIp()
    }
    
    private func logToFile(_ message: String) {
        let logPath = "/Users/enoch/.gemini/antigravity/app.log"
        let timestamp = Date().description
        let logLine = "[\(timestamp)] \(message)\n"
        if let data = logLine.data(using: .utf8) {
            if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            } else {
                try? logLine.write(toFile: logPath, atomically: true, encoding: .utf8)
            }
        }
    }
    
    func connect() {
        disconnect() // Clean up any existing connection
        
        let host = NWEndpoint.Host(switcherIp)
        let port = NWEndpoint.Port(rawValue: 1000) ?? 1000
        
        let conn = NWConnection(host: host, port: port, using: .udp)
        self.connection = conn
        
        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    print("RGBLink socket ready to send to \(self.switcherIp)")
                    self.startReceiving()
                    self.startLivenessChecking()
                case .failed, .cancelled:
                    self.stopLivenessChecking()
                    self.isConnected = false
                    print("RGBLink socket closed or failed")
                default:
                    break
                }
            }
        }
        conn.start(queue: queue)
    }
    
    func disconnect() {
        sendDisconnectMessage()
        stopLivenessChecking()
        connection?.cancel()
        connection = nil
        DispatchQueue.main.async {
            self.isConnected = false
            self.pgmSource = -1
            self.pstSource = -1
        }
    }
    
    private func startLivenessChecking() {
        stopLivenessChecking()
        lastFeedbackTime = nil
        
        DispatchQueue.main.async {
            self.sendLivenessPoll()
            
            self.checkTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.sendLivenessPoll()
                
                let now = Date()
                if let lastTime = self.lastFeedbackTime {
                    let elapsed = now.timeIntervalSince(lastTime)
                    if elapsed > 20.0 {
                        if self.isConnected {
                            self.isConnected = false
                            self.pgmSource = -1
                            self.pstSource = -1
                            print("RGBLink connection timeout: no feedback received")
                        }
                    } else {
                        if !self.isConnected {
                            self.isConnected = true
                        }
                    }
                } else {
                    if self.isConnected {
                        self.isConnected = false
                        self.pgmSource = -1
                        self.pstSource = -1
                    }
                }
            }
        }
    }
    
    private func stopLivenessChecking() {
        checkTimer?.invalidate()
        checkTimer = nil
        lastFeedbackTime = nil
    }
    
    private func sendLivenessPoll() {
        // Query device model ONLY (acts as a light ping to prevent CPU congestion on the switcher)
        sendCommand(cmd: "68", dat1: "01", dat2: "00", dat3: "00", dat4: "00")
        // Query active PGM & PST sources
        sendCommand(cmd: "75", dat1: "03", dat2: "00", dat3: "00", dat4: "01")
        sendCommand(cmd: "75", dat1: "03", dat2: "00", dat3: "00", dat4: "00")
    }
    
    private func startReceiving() {
        connection?.receiveMessage { [weak self] content, context, isComplete, error in
            guard let self = self else { return }
            if let data = content, !data.isEmpty {
                self.parseFeedback(data: data)
            }
            if error == nil && self.connection?.state == .ready {
                self.startReceiving()
            }
        }
    }
    
    private func parseFeedback(data: Data) {
        let hexString = data.map { String(format: "%02hhX", $0) }.joined()
        self.logToFile("UDP RX Raw Length: \(data.count), Hex: \(hexString)")
        
        DispatchQueue.main.async {
            self.lastFeedbackTime = Date()
            if !self.isConnected {
                self.isConnected = true
                print("RGBLink connection verified by feedback packet")
            }
        }
        
        /*
        // 22-byte binary status response (Disabled due to firmware register bugs on Mini Edge)
        if data.count == 22 {
            let prev = data[0]
            let src = data[2]
            DispatchQueue.main.async {
                if prev <= 3 {
                    self.pstSource = Int(prev)
                }
                if src <= 3 {
                    self.pgmSource = Int(src)
                }
            }
            return
        }
        */
        
        // Standard 19-byte ASCII response
        guard data.count >= 19 else { return }
        if let str = String(data: data, encoding: .utf8) {
            let cleanStr = str.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard cleanStr.hasPrefix("<F") && cleanStr.hasSuffix(">") else { return }
            
            let chars = Array(cleanStr)
            guard chars.count >= 19 else { return }
            
            let cmd = String(chars[6...7])
            let dat1 = String(chars[8...9])
            let dat2 = String(chars[10...11])
            let dat3 = String(chars[12...13])
            let dat4 = String(chars[14...15])
            
            self.logToFile("UDP RX: \(cleanStr) -> cmd=\(cmd) dat1=\(dat1) dat2=\(dat2) dat3=\(dat3) dat4=\(dat4)")
            
            DispatchQueue.main.async {
                if cmd == "75" {
                    if dat1 == "02" || dat1 == "03" {
                        if let src = Int(dat3, radix: 16), let out = Int(dat4, radix: 16) {
                            if src >= 0 && src <= 3 {
                                self.logToFile("  Parse 75: src=\(src), output=\(out) (PGM=\(self.pgmSource), PST=\(self.pstSource))")
                                if out == 0 { // PST
                                    self.pstSource = src
                                } else if out == 1 { // PGM
                                    self.pgmSource = src
                                }
                                self.logToFile("    Result 75: (PGM=\(self.pgmSource), PST=\(self.pstSource))")
                            }
                        }
                    } else if dat1 == "1E" || dat1 == "1F" {
                        if let pip = Int(dat3, radix: 16) {
                            self.pipMode = pip
                        }
                    }
                } else if cmd == "78" {
                    if dat1 == "00" {
                        self.logToFile("  Parse 78 swap (PGM=\(self.pgmSource), PST=\(self.pstSource))")
                        let temp = self.pgmSource
                        self.pgmSource = self.pstSource
                        self.pstSource = temp
                        self.logToFile("    Result 78 swap: (PGM=\(self.pgmSource), PST=\(self.pstSource))")
                    } else if dat1 == "06" || dat1 == "07" {
                        if let effect = Int(dat2, radix: 16) {
                            self.switchEffect = effect
                        }
                    }
                }
            }
        }
    }
    
    func sendCommand(cmd: String, dat1: String, dat2: String, dat3: String, dat4: String) {
        let addr = "00"
        let sn = String(format: "%02X", nextSn)
        incrementSn()
        
        let checksum = calculateChecksum(addr: addr, sn: sn, cmd: cmd, dat1: dat1, dat2: dat2, dat3: dat3, dat4: dat4)
        let packetStr = "<T\(addr)\(sn)\(cmd)\(dat1)\(dat2)\(dat3)\(dat4)\(checksum)>"
        self.logToFile("UDP TX: \(packetStr)")
        
        guard let data = packetStr.data(using: .utf8) else { return }
        
        connection?.send(content: data, completion: .contentProcessed({ error in
            if let error = error {
                self.logToFile("UDP TX error: \(error.localizedDescription)")
            }
        }))
    }
    
    private func incrementSn() {
        nextSn = (nextSn == 255) ? 0 : (nextSn + 1)
    }
    
    private func calculateChecksum(addr: String, sn: String, cmd: String, dat1: String, dat2: String, dat3: String, dat4: String) -> String {
        let items = [addr, sn, cmd, dat1, dat2, dat3, dat4]
        var sum = 0
        for item in items {
            sum += Int(item, radix: 16) ?? 0
        }
        let checksumByte = sum % 256
        return String(format: "%02X", checksumByte)
    }
    
    private func sendConnectMessage() {
        sendCommand(cmd: "68", dat1: "66", dat2: "01", dat3: "00", dat4: "00")
    }
    
    private func sendDisconnectMessage() {
        sendCommand(cmd: "68", dat1: "66", dat2: "00", dat3: "00", dat4: "00")
    }
    
    func setPgmSource(_ source: Int) {
        let sourceHex = String(format: "%02X", source)
        sendCommand(cmd: "75", dat1: "02", dat2: "00", dat3: sourceHex, dat4: "01")
        self.pgmSource = source
    }
    
    func setPstSource(_ source: Int) {
        let sourceHex = String(format: "%02X", source)
        sendCommand(cmd: "75", dat1: "02", dat2: "00", dat3: sourceHex, dat4: "00")
        self.pstSource = source
    }
    
    func sendCut() {
        sendCommand(cmd: "78", dat1: "00", dat2: "00", dat3: "01", dat4: "00")
    }
    
    func sendAuto() {
        sendCommand(cmd: "78", dat1: "00", dat2: "00", dat3: "00", dat4: "00")
    }
    
    func setPipMode(_ mode: Int) {
        let modeHex = String(format: "%02X", mode)
        sendCommand(cmd: "75", dat1: "1E", dat2: "00", dat3: modeHex, dat4: "00")
        self.pipMode = mode
    }
    
    func setTransitionEffect(_ effect: Int) {
        let effectHex = String(format: "%02X", effect)
        sendCommand(cmd: "78", dat1: "06", dat2: effectHex, dat3: "00", dat4: "00")
        self.switchEffect = effect
    }
}
