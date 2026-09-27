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

final class PipeStreamManager {
    static let shared = PipeStreamManager()
    private var processes: [Int: Process] = [:]
    private var pipes: [Int: Pipe] = [:]
    private var frameCounters: [Int: Int] = [:]
    private var buffers: [Int: Data] = [:]
    private let lock = NSLock()
    
    private init() {}
    
    func startStream(index: Int, rtspUrl: String, onFrame: @escaping (NSImage) -> Void) {
        stopStream(index: index)
        
        guard !rtspUrl.isEmpty else {
            AppLogger.log("⚠️ [PipeStreamManager \(index)] Empty RTSP URL, skipping stream start")
            return
        }
        
        AppLogger.log("🚀 [PipeStreamManager \(index)] STARTING RTSP Pipe stream: \(rtspUrl)")
        
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        if !FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ffmpeg") {
            process.executableURL = URL(fileURLWithPath: "/usr/local/bin/ffmpeg")
        }
        
        process.arguments = [
            "-loglevel", "quiet",
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
        
        do {
            try process.run()
            AppLogger.log("✅ [PipeStreamManager \(index)] FFmpeg Pipe PID: \(process.processIdentifier)")
        } catch {
            AppLogger.log("❌ [PipeStreamManager \(index)] ERROR starting ffmpeg: \(error)")
        }
    }
    
    func stopStream(index: Int) {
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
            AppLogger.log("🛑 [PipeStreamManager \(index)] STOPPING Stream PID: \(proc.processIdentifier)")
            proc.terminate()
        }
    }
    
    func getFrameCount(index: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return frameCounters[index, default: 0]
    }
}
