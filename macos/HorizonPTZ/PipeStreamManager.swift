import Foundation
import AppKit

final class AppLogger {
    static let logFile = "/tmp/horizon_ai.log"
    static func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        if let data = line.data(using: .utf8) {
            if let handle = FileHandle(forWritingAtPath: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: logFile))
            }
        }
        print(line)
        fflush(stdout)
    }
}

final class PipeStreamManager: ObservableObject {
    static let shared = PipeStreamManager()
    
    @Published var isAvailable: Bool = false
    @Published var ffmpegPath: String? = nil
    
    private struct StreamInfo {
        let rtspUrl: String
        let onFrame: (NSImage) -> Void
        var lastFrameTime: Date
        var isManualStop: Bool
    }
    
    private var processes: [Int: Process] = [:]
    private var pipes: [Int: Pipe] = [:]
    private var frameCounters: [Int: Int] = [:]
    private var buffers: [Int: Data] = [:]
    private var streamInfos: [Int: StreamInfo] = [:]
    private var watchdogTimer: Timer? = nil
    private let lock = NSLock()
    
    private init() {
        checkAvailability()
        startWatchdog()
    }
    
    @discardableResult
    func checkAvailability() -> Bool {
        let url = PipeStreamManager.findFFmpegURL()
        let available = (url != nil)
        let path = url?.path
        if Thread.isMainThread {
            self.isAvailable = available
            self.ffmpegPath = path
        } else {
            DispatchQueue.main.async {
                self.isAvailable = available
                self.ffmpegPath = path
            }
        }
        return available
    }
    
    func startStream(index: Int, rtspUrl: String, onFrame: @escaping (NSImage) -> Void) {
        lock.lock()
        streamInfos[index] = StreamInfo(rtspUrl: rtspUrl, onFrame: onFrame, lastFrameTime: Date(), isManualStop: false)
        lock.unlock()
        
        spawnProcess(index: index, rtspUrl: rtspUrl, onFrame: onFrame)
    }
    
    static func findFFmpegURL() -> URL? {
        // 1. App Bundle Resources
        if let bundlePath = Bundle.main.resourceURL?.appendingPathComponent("ffmpeg").path,
           FileManager.default.isExecutableFile(atPath: bundlePath) {
            return URL(fileURLWithPath: bundlePath)
        }
        
        // 2. Common system & Homebrew paths (Intel: /usr/local/bin, Apple Silicon: /opt/homebrew/bin)
        let candidates = [
            "/usr/local/bin/ffmpeg",    // Intel Mac Homebrew default
            "/opt/homebrew/bin/ffmpeg", // Apple Silicon Homebrew default
            "/usr/bin/ffmpeg",          // System path
            "/opt/local/bin/ffmpeg",    // MacPorts
            "/usr/pkg/bin/ffmpeg"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        
        // 3. User local bin
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let userCandidates = [
            "\(home)/.local/bin/ffmpeg",
            "\(home)/bin/ffmpeg"
        ]
        for path in userCandidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        
        return nil
    }
    
    static var isFFmpegAvailable: Bool {
        return findFFmpegURL() != nil
    }

    private func spawnProcess(index: Int, rtspUrl: String, onFrame: @escaping (NSImage) -> Void) {
        stopProcessOnly(index: index)
        
        guard !rtspUrl.isEmpty else {
            AppLogger.log("⚠️ [PipeStreamManager \(index)] Empty RTSP URL, skipping stream start")
            return
        }
        
        guard let ffmpegURL = PipeStreamManager.findFFmpegURL() else {
            AppLogger.log("❌ [PipeStreamManager \(index)] FFmpeg not found on this Mac! Please install via 'brew install ffmpeg' to enable AI people counting.")
            return
        }
        
        AppLogger.log("🚀 [PipeStreamManager \(index)] Spawning RTSP Pipe stream via \(ffmpegURL.path): \(rtspUrl)")
        
        let pipe = Pipe()
        let process = Process()
        process.executableURL = ffmpegURL
        
        // Use -timeout 3000000 (3s TCP timeout) so disconnects are detected fast
        process.arguments = [
            "-loglevel", "quiet",
            "-timeout", "3000000",
            "-rtsp_transport", "tcp",
            "-i", rtspUrl,
            "-vf", "fps=10,scale=640:-1",
            "-f", "image2pipe",
            "-vcodec", "mjpeg",
            "-"
        ]
        
        process.standardOutput = pipe
        
        lock.lock()
        pipes[index] = pipe
        processes[index] = process
        frameCounters[index] = 0
        buffers[index] = Data()
        lock.unlock()
        
        let outHandle = pipe.fileHandleForReading
        outHandle.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            
            var framesToProcess: [NSImage] = []
            
            self.lock.lock()
            self.buffers[index, default: Data()].append(chunk)
            var buffer = self.buffers[index]!
            
            let soi = Data([0xFF, 0xD8])
            let eoi = Data([0xFF, 0xD9])
            
            while let soiRange = buffer.range(of: soi) {
                if soiRange.lowerBound > 0 {
                    buffer.removeSubrange(0..<soiRange.lowerBound)
                }
                
                guard let eoiRange = buffer.range(of: eoi) else {
                    break
                }
                
                let frameEnd = eoiRange.upperBound
                let jpegData = buffer.subdata(in: 0..<frameEnd)
                buffer.removeSubrange(0..<frameEnd)
                
                if let image = NSImage(data: jpegData) {
                    self.frameCounters[index, default: 0] += 1
                    let count = self.frameCounters[index, default: 0]
                    self.streamInfos[index]?.lastFrameTime = Date()
                    
                    if count % 30 == 0 {
                        AppLogger.log("📸 [PipeStreamManager \(index)] Frame #\(count) extracted in RAM!")
                    }
                    framesToProcess.append(image)
                }
            }
            
            if buffer.count > 500_000 {
                buffer.removeAll()
            }
            self.buffers[index] = buffer
            self.lock.unlock()
            
            if let latestImage = framesToProcess.last {
                DispatchQueue.main.async {
                    onFrame(latestImage)
                }
            }
        }
        
        process.terminationHandler = { [weak self] proc in
            guard let self = self else { return }
            self.lock.lock()
            let isManual = self.streamInfos[index]?.isManualStop ?? true
            self.lock.unlock()
            
            if !isManual {
                AppLogger.log("⚠️ [PipeStreamManager \(index)] FFmpeg process exited (code \(proc.terminationStatus)). Auto-reconnecting in 2s...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    guard let self = self else { return }
                    self.lock.lock()
                    guard let info = self.streamInfos[index], !info.isManualStop else {
                        self.lock.unlock()
                        return
                    }
                    self.lock.unlock()
                    self.spawnProcess(index: index, rtspUrl: info.rtspUrl, onFrame: info.onFrame)
                }
            }
        }
        
        do {
            try process.run()
            AppLogger.log("✅ [PipeStreamManager \(index)] FFmpeg Pipe PID: \(process.processIdentifier)")
        } catch {
            AppLogger.log("❌ [PipeStreamManager \(index)] ERROR starting ffmpeg: \(error)")
        }
    }
    
    private func stopProcessOnly(index: Int) {
        lock.lock()
        let pipe = pipes.removeValue(forKey: index)
        let proc = processes.removeValue(forKey: index)
        frameCounters.removeValue(forKey: index)
        buffers.removeValue(forKey: index)
        lock.unlock()
        
        if let pipe = pipe {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
        if let proc = proc {
            proc.terminationHandler = nil
            AppLogger.log("🛑 [PipeStreamManager \(index)] STOPPING Stream PID: \(proc.processIdentifier)")
            proc.terminate()
        }
    }
    
    func stopStream(index: Int) {
        lock.lock()
        streamInfos[index]?.isManualStop = true
        streamInfos.removeValue(forKey: index)
        lock.unlock()
        
        stopProcessOnly(index: index)
    }
    
    func getFrameCount(index: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return frameCounters[index, default: 0]
    }
    
    // MARK: - Auto-Healing Watchdog
    private func startWatchdog() {
        DispatchQueue.main.async { [weak self] in
            self?.watchdogTimer?.invalidate()
            self?.watchdogTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
                self?.checkAndHealStreams()
            }
        }
    }
    
    private func checkAndHealStreams() {
        lock.lock()
        let activeIndices = Array(streamInfos.keys)
        var streamsToRestart: [(Int, String, (NSImage) -> Void)] = []
        
        for idx in activeIndices {
            guard let info = streamInfos[idx], !info.isManualStop, !info.rtspUrl.isEmpty else { continue }
            let isRunning = processes[idx]?.isRunning ?? false
            let idleTime = Date().timeIntervalSince(info.lastFrameTime)
            
            // If process exited or no frames received for > 5.0 seconds
            if !isRunning || idleTime > 5.0 {
                AppLogger.log("🩺 [PipeStreamManager Watchdog \(idx)] Inactive AI stream detected (running=\(isRunning), idle=\(String(format: "%.1f", idleTime))s). Auto-healing...")
                streamsToRestart.append((idx, info.rtspUrl, info.onFrame))
            }
        }
        lock.unlock()
        
        for (idx, url, onFrame) in streamsToRestart {
            spawnProcess(index: idx, rtspUrl: url, onFrame: onFrame)
        }
    }
}
