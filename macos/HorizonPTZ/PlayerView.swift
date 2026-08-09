import SwiftUI
import VLCKit
import Vision

class AppLogger {
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

class PlayerViewModel: ObservableObject {
    let mediaPlayer = VLCMediaPlayer()
    
    deinit {
        mediaPlayer.drawable = nil
        mediaPlayer.stop()
    }
}

class PipeStreamManager {
    static let shared = PipeStreamManager()
    private var processes: [Int: Process] = [:]
    private var pipes: [Int: Pipe] = [:]
    private var frameCounters: [Int: Int] = [:]
    
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
        
        pipes[index] = pipe
        processes[index] = process
        frameCounters[index] = 0
        
        let outHandle = pipe.fileHandleForReading
        outHandle.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }
            let data = handle.availableData
            guard !data.isEmpty else { return }
            
            if let image = NSImage(data: data) {
                self.frameCounters[index, default: 0] += 1
                let count = self.frameCounters[index, default: 0]
                if count % 30 == 0 {
                    AppLogger.log("📸 [PipeStreamManager \(index)] Frame #\(count) extracted in RAM!")
                }
                DispatchQueue.main.async {
                    onFrame(image)
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
        if let pipe = pipes[index] {
            pipe.fileHandleForReading.readabilityHandler = nil
            pipes.removeValue(forKey: index)
        }
        if let proc = processes[index] {
            AppLogger.log("🛑 [PipeStreamManager \(index)] STOPPING Stream PID: \(proc.processIdentifier)")
            proc.terminate()
            processes.removeValue(forKey: index)
        }
        frameCounters.removeValue(forKey: index)
    }
    
    func getFrameCount(index: Int) -> Int {
        return frameCounters[index, default: 0]
    }
}

struct VLCVideoPlayer: NSViewRepresentable {
    let rtspUrl: String
    let mediaPlayer: VLCMediaPlayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor

        mediaPlayer.drawable = view

        if !rtspUrl.isEmpty {
            AppLogger.log("🎥 [VLCVideoPlayer] Loading RTSP URL: \(rtspUrl)")
            mediaPlayer.media = VLCMedia(url: URL(string: rtspUrl)!)
            mediaPlayer.play()
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if mediaPlayer.media?.url?.absoluteString != rtspUrl, !rtspUrl.isEmpty {
            AppLogger.log("🎥 [VLCVideoPlayer] Updating RTSP URL to: \(rtspUrl)")
            mediaPlayer.media = VLCMedia(url: URL(string: rtspUrl)!)
            mediaPlayer.play()
        }
    }
}

struct LiveAIBoundingBoxCanvas: View {
    let trackedHumans: [TrackedHuman]
    let count: Int
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Top-Left AI People Counter Badge
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("AI 即時人數: \(count) 人")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.75))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.green.opacity(0.5), lineWidth: 1)
                )
                .padding(10)
                
                // Vector Bounding Boxes
                ForEach(trackedHumans, id: \.id) { human in
                    let rect = human.box
                    let vx = rect.origin.x * geo.size.width
                    let vy = (1.0 - rect.origin.y - rect.height) * geo.size.height
                    let vw = rect.width * geo.size.width
                    let vh = rect.height * geo.size.height
                    
                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .stroke(Color.green, lineWidth: 2.5)
                            .background(Color.green.opacity(0.12))
                        
                        Text("\(human.id)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .cornerRadius(4)
                            .offset(x: 2, y: 2)
                    }
                    .frame(width: max(0, vw), height: max(0, vh))
                    .position(x: vx + vw / 2, y: vy + vh / 2)
                }
            }
        }
    }
}

struct PlayerView: View {
    let rtspUrl: String
    let index: Int
    @Binding var isAiEnabled: Bool
    
    @StateObject private var viewModel = PlayerViewModel()
    @State private var liveHumans: [TrackedHuman] = []
    @State private var liveCount: Int = 0
    @State private var isAnalyzing = false
    @State private var startupTimer: Timer? = nil
    
    var body: some View {
        ZStack {
            // Live Playing RTSP Video Stream
            VLCVideoPlayer(rtspUrl: rtspUrl, mediaPlayer: viewModel.mediaPlayer)
            
            // Transparent SwiftUI Canvas Overlay
            if isAiEnabled {
                LiveAIBoundingBoxCanvas(trackedHumans: liveHumans, count: liveCount)
            }
        }
        .onAppear {
            AppLogger.log("👁️ [PlayerView \(index)] onAppear. isAiEnabled=\(isAiEnabled)")
            startAiWithWatchdog()
        }
        .onDisappear {
            AppLogger.log("👁️ [PlayerView \(index)] onDisappear.")
            stopAiStream()
            startupTimer?.invalidate()
        }
        .onChange(of: isAiEnabled) { newValue in
            AppLogger.log("🔄 [PlayerView \(index)] isAiEnabled changed to \(newValue)")
            if newValue {
                startAiWithWatchdog()
            } else {
                stopAiStream()
            }
        }
        .onChange(of: rtspUrl) { newUrl in
            AppLogger.log("🔄 [PlayerView \(index)] RTSP URL changed to: \(newUrl)")
            if isAiEnabled {
                startAiWithWatchdog()
            }
        }
    }
    
    private func startAiWithWatchdog() {
        updateAiStream()
        
        // Startup Watchdog: If after 1.5 seconds no frames have been processed, auto-heal and restart AI stream!
        startupTimer?.invalidate()
        startupTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
            if self.isAiEnabled {
                let frames = PipeStreamManager.shared.getFrameCount(index: self.index)
                if frames == 0 {
                    AppLogger.log("🩺 [PlayerView Watchdog \(index)] No frames received after 1.5s startup, auto-healing AI stream!")
                    self.updateAiStream()
                }
            }
        }
    }
    
    private func updateAiStream() {
        if isAiEnabled {
            PipeStreamManager.shared.startStream(index: index, rtspUrl: rtspUrl) { image in
                guard self.isAiEnabled, !self.isAnalyzing else { return }
                self.isAnalyzing = true
                
                PeopleCounterService.shared.analyzePeopleCount(in: image, cameraIndex: self.index) { result in
                    if self.isAiEnabled {
                        self.liveHumans = result.trackedHumans
                        self.liveCount = result.count
                    }
                    self.isAnalyzing = false
                }
            }
        } else {
            stopAiStream()
        }
    }
    
    private func stopAiStream() {
        liveHumans = []
        liveCount = 0
        PipeStreamManager.shared.stopStream(index: index)
    }
}
