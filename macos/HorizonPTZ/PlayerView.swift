import SwiftUI
import VLCKit
import Vision

final class PlayerViewModel: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    let mediaPlayer = VLCMediaPlayer()
    var rtspUrl: String = ""
    var cameraIndex: Int = 1
    
    @Published var isReconnecting: Bool = false
    private var lastActiveTime: Date = Date()
    private var watchdogTimer: Timer? = nil
    private var isManualStop: Bool = false
    
    override init() {
        super.init()
        mediaPlayer.delegate = self
    }
    
    deinit {
        stop()
    }
    
    func start(rtspUrl: String, cameraIndex: Int) {
        self.rtspUrl = rtspUrl
        self.cameraIndex = cameraIndex
        self.isManualStop = false
        self.lastActiveTime = Date()
        
        loadAndPlay(url: rtspUrl)
        startWatchdog()
    }
    
    func updateUrl(newUrl: String) {
        guard newUrl != rtspUrl else { return }
        self.rtspUrl = newUrl
        loadAndPlay(url: newUrl)
    }
    
    func stop() {
        isManualStop = true
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        mediaPlayer.delegate = nil
        mediaPlayer.drawable = nil
        mediaPlayer.stop()
    }
    
    private func loadAndPlay(url: String) {
        guard !url.isEmpty, let targetUrl = URL(string: url) else { return }
        AppLogger.log("🎥 [PlayerViewModel \(cameraIndex)] Loading RTSP URL: \(url)")
        let media = VLCMedia(url: targetUrl)
        // Optimized RTSP network caching (300ms) for real-time responsiveness & TCP transport
        media.addOptions([
            "network-caching": 300,
            "rtsp-tcp": ""
        ])
        mediaPlayer.media = media
        mediaPlayer.play()
    }
    
    private var isConnectingAttempt: Bool = false
    
    func reconnect() {
        guard !isManualStop, !rtspUrl.isEmpty, !isConnectingAttempt else { return }
        isConnectingAttempt = true
        lastActiveTime = Date()
        
        DispatchQueue.main.async {
            self.isReconnecting = true
        }
        AppLogger.log("🔄 [PlayerViewModel \(cameraIndex)] Auto-reconnecting RTSP stream: \(rtspUrl)")
        mediaPlayer.stop()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self = self, !self.isManualStop else { return }
            self.loadAndPlay(url: self.rtspUrl)
            self.isConnectingAttempt = false
        }
    }
    
    // MARK: - VLCMediaPlayerDelegate
    func mediaPlayerStateChanged(_ aNotification: Notification) {
        let state = mediaPlayer.state
        AppLogger.log("📺 [VLC State \(cameraIndex)] State changed: \(state.rawValue)")
        
        DispatchQueue.main.async {
            switch state {
            case .playing:
                self.isConnectingAttempt = false
                self.isReconnecting = false
                self.lastActiveTime = Date()
            case .opening, .buffering:
                self.lastActiveTime = Date()
            case .error, .ended, .stopped:
                if !self.isManualStop && !self.isConnectingAttempt {
                    self.isReconnecting = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        guard let self = self, !self.isManualStop else { return }
                        let s = self.mediaPlayer.state
                        if !self.mediaPlayer.isPlaying && s != .opening && s != .buffering {
                            self.reconnect()
                        }
                    }
                }
            default:
                break
            }
        }
    }
    
    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        lastActiveTime = Date()
        isConnectingAttempt = false
        if isReconnecting {
            DispatchQueue.main.async {
                self.isReconnecting = false
            }
        }
    }
    
    private func startWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self = self, !self.isManualStop, !self.rtspUrl.isEmpty else { return }
            
            let isPlaying = self.mediaPlayer.isPlaying
            let state = self.mediaPlayer.state
            let idleTime = Date().timeIntervalSince(self.lastActiveTime)
            
            // Allow up to 8s during initial opening / buffering
            if state == .opening || state == .buffering {
                if idleTime > 8.0 {
                    AppLogger.log("🩺 [PlayerViewModel Watchdog \(self.cameraIndex)] Stuck in opening/buffering >8s. Auto-reconnecting...")
                    self.reconnect()
                }
                return
            }
            
            // Reconnect if not playing (error/stopped/ended) OR stream frozen for > 5.0s
            if !isPlaying || state == .error || state == .stopped || state == .ended || idleTime > 5.0 {
                AppLogger.log("🩺 [PlayerViewModel Watchdog \(self.cameraIndex)] Disconnect or freeze detected (playing=\(isPlaying), state=\(state.rawValue), idle=\(String(format: "%.1f", idleTime))s). Auto-reconnecting...")
                self.reconnect()
            }
        }
    }
}

struct VLCVideoPlayer: NSViewRepresentable {
    let rtspUrl: String
    let viewModel: PlayerViewModel
    let cameraIndex: Int

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor

        viewModel.mediaPlayer.drawable = view
        viewModel.start(rtspUrl: rtspUrl, cameraIndex: cameraIndex)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if viewModel.mediaPlayer.drawable == nil {
            viewModel.mediaPlayer.drawable = nsView
        }
        viewModel.updateUrl(newUrl: rtspUrl)
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
    
    var body: some View {
        ZStack {
            // Live Playing RTSP Video Stream
            VLCVideoPlayer(rtspUrl: rtspUrl, viewModel: viewModel, cameraIndex: index)
            
            // Transparent SwiftUI Canvas Overlay
            if isAiEnabled {
                LiveAIBoundingBoxCanvas(trackedHumans: liveHumans, count: liveCount)
            }
            
            // Missing FFmpeg Alert Badge Overlay
            if isAiEnabled && !PipeStreamManager.isFFmpegAvailable {
                VStack {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                            .font(.system(size: 13, weight: .bold))
                        Text("未偵測到 FFmpeg：請開啟終端機執行 brew install ffmpeg 以啟用 AI 計算")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.85))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.yellow.opacity(0.8), lineWidth: 1)
                    )
                    .shadow(radius: 4)
                    .padding(.top, 12)
                    
                    Spacer()
                }
                .transition(.opacity)
            }
            
            // Reconnecting Alert Badge Overlay
            if viewModel.isReconnecting {
                VStack {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("訊號中斷，自動重連中...")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.red.opacity(0.88))
                    .cornerRadius(8)
                    .shadow(radius: 4)
                    .padding(.top, 12)
                    
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            AppLogger.log("👁️ [PlayerView \(index)] onAppear. isAiEnabled=\(isAiEnabled)")
            updateAiStream()
        }
        .onDisappear {
            AppLogger.log("👁️ [PlayerView \(index)] onDisappear.")
            viewModel.stop()
            stopAiStream()
        }
        .onChange(of: isAiEnabled) { newValue in
            AppLogger.log("🔄 [PlayerView \(index)] isAiEnabled changed to \(newValue)")
            if newValue {
                updateAiStream()
            } else {
                stopAiStream()
            }
        }
        .onChange(of: rtspUrl) { newUrl in
            AppLogger.log("🔄 [PlayerView \(index)] RTSP URL changed to: \(newUrl)")
            viewModel.updateUrl(newUrl: newUrl)
            if isAiEnabled {
                updateAiStream()
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
