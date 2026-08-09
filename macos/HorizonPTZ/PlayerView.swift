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
    
    func startStream(index: Int, rtspUrl: String, onFrame: @escaping (NSImage) -> Void) {
        stopStream(index: index)
        AppLogger.log("🚀 [PipeStreamManager \(index)] STARTING RTSP Pipe stream: \(rtspUrl)")
        
        let ffmpegPath = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ffmpeg") ? "/opt/homebrew/bin/ffmpeg" : "/usr/local/bin/ffmpeg"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = [
            "-loglevel", "warning",
            "-fflags", "nobuffer+fastseek",
            "-flags", "low_delay",
            "-rtsp_transport", "tcp",
            "-i", rtspUrl,
            "-vf", "fps=6,scale=1080:-1",
            "-q:v", "3",
            "-f", "image2pipe",
            "-vcodec", "mjpeg",
            "pipe:1"
        ]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        processes[index] = process
        pipes[index] = pipe
        
        var buffer = Data()
        var count = 0
        
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { return }
            
            buffer.append(chunk)
            
            // Drain buffer & extract JPEG frames safely in isolated thread-safe closure
            while let eoiRange = buffer.range(of: Data([0xFF, 0xD9])) {
                let frameData = buffer.subdata(in: 0..<eoiRange.upperBound)
                buffer.removeSubrange(0..<eoiRange.upperBound)
                
                if let image = NSImage(data: frameData), image.size.width > 0 {
                    count += 1
                    AppLogger.log("📸 [PipeStreamManager \(index)] Frame #\(count) extracted in RAM!")
                    DispatchQueue.main.async {
                        onFrame(image)
                    }
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
            pipes[index] = nil
        }
        if let proc = processes[index] {
            AppLogger.log("🛑 [PipeStreamManager \(index)] STOPPING Stream PID: \(proc.processIdentifier)")
            proc.terminate()
            processes[index] = nil
        }
    }
}

struct LiveAIBoundingBoxCanvas: View {
    let trackedHumans: [TrackedHuman]
    let count: Int
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Render transparent green bounding boxes with PERSISTENT IDs over the live playing video
                ForEach(trackedHumans, id: \.id) { human in
                    let box = human.box
                    let w = box.size.width * geo.size.width
                    let h = box.size.height * geo.size.height
                    let x = box.origin.x * geo.size.width
                    let y = (1.0 - box.origin.y - box.size.height) * geo.size.height // Vision Y is bottom-up (0..1), SwiftUI Y is top-down
                    
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(red: 0.0, green: 0.95, blue: 0.35, opacity: 1.0), lineWidth: 2.5)
                            .background(Color(red: 0.0, green: 0.95, blue: 0.35, opacity: 0.12))
                        
                        Text("\(human.id)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(red: 0.0, green: 0.75, blue: 0.25, opacity: 0.95))
                            .cornerRadius(4)
                            .offset(x: 2, y: 2)
                    }
                    .frame(width: max(w, 10), height: max(h, 10))
                    .position(x: x + w/2, y: y + h/2)
                    .animation(.linear(duration: 0.12), value: x)
                    .animation(.linear(duration: 0.12), value: y)
                }
                
                // Live count badge overlay on top left of video player
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("AI 即時人數: \(count) 人")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.75))
                .cornerRadius(6)
                .padding(10)
            }
        }
        .allowsHitTesting(false)
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
    
    var body: some View {
        ZStack {
            // Live Playing RTSP Video Stream (Always runs smoothly without freezing)
            VLCVideoPlayer(rtspUrl: rtspUrl, mediaPlayer: viewModel.mediaPlayer)
            
            // Transparent SwiftUI Canvas Overlay (Renders ONLY vector bounding boxes with PERSISTENT IDs)
            if isAiEnabled {
                LiveAIBoundingBoxCanvas(trackedHumans: liveHumans, count: liveCount)
            }
        }
        .onAppear {
            AppLogger.log("👁️ [PlayerView \(index)] onAppear. isAiEnabled=\(isAiEnabled)")
            updateAiStream()
        }
        .onDisappear {
            AppLogger.log("👁️ [PlayerView \(index)] onDisappear.")
            stopAiStream()
        }
        .onChange(of: isAiEnabled) { newValue in
            AppLogger.log("🔄 [PlayerView \(index)] isAiEnabled changed to \(newValue)")
            updateAiStream()
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
        isAnalyzing = false
        PipeStreamManager.shared.stopStream(index: index)
        PeopleCounterService.shared.resetTracker(cameraIndex: index)
    }
}

class VLCVideoContainerView: NSView {
    weak var mediaPlayer: VLCMediaPlayer?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.black.cgColor
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func cleanup() {
        if let player = mediaPlayer {
            player.drawable = nil
        }
        self.subviews.forEach { $0.removeFromSuperview() }
    }
}

struct VLCVideoPlayer: NSViewRepresentable {
    let rtspUrl: String
    let mediaPlayer: VLCMediaPlayer
    
    func makeNSView(context: Context) -> VLCVideoContainerView {
        let container = VLCVideoContainerView()
        container.mediaPlayer = mediaPlayer
        mediaPlayer.drawable = container
        
        startPlayback()
        return container
    }
    
    func updateNSView(_ nsView: VLCVideoContainerView, context: Context) {
        if let currentMedia = mediaPlayer.media,
           let currentUrl = currentMedia.url,
           currentUrl.absoluteString != rtspUrl {
            startPlayback()
        }
    }
    
    static func dismantleNSView(_ nsView: VLCVideoContainerView, coordinator: ()) {
        nsView.cleanup()
    }
    
    private func startPlayback() {
        guard let url = URL(string: rtspUrl) else { return }
        
        if let currentMedia = mediaPlayer.media, currentMedia.url == url, mediaPlayer.isPlaying {
            return
        }
        
        let media = VLCMedia(url: url)
        media.addOption(":network-caching=30")
        media.addOption(":live-caching=0")
        media.addOption(":drop-late-frames")
        media.addOption(":avcodec-hw=any")
        media.addOption(":no-audio")
        media.addOption(":no-sub-autodetect-file")
        
        mediaPlayer.media = media
        mediaPlayer.play()
    }
}
