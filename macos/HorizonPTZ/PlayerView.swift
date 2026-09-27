import SwiftUI
import VLCKit
import Vision

class PlayerViewModel: ObservableObject {
    let mediaPlayer = VLCMediaPlayer()
    
    deinit {
        mediaPlayer.drawable = nil
        mediaPlayer.stop()
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
                        AppLogger.log("🎯 [PlayerView \(self.index)] AI Detection Count = \(result.count) | Tracked IDs: \(result.trackedHumans.map { $0.id })")
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
