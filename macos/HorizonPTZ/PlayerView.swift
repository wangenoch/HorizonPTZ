import SwiftUI
import VLCKit
import Vision

final class PlayerViewModel: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    let mediaPlayer = VLCMediaPlayer()
    var rtspUrl: String = ""
    var cameraIndex: Int = 1
    
    // 弱引用底層視頻渲染容器視圖，供 AI 即時記憶體畫面擷取
    weak var containerView: NSView? = nil
    
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
        containerView = nil
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

        viewModel.containerView = view
        viewModel.mediaPlayer.drawable = view
        viewModel.start(rtspUrl: rtspUrl, cameraIndex: cameraIndex)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        viewModel.containerView = nsView
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
    @State private var aiSamplingTimer: Timer? = nil
    
    var body: some View {
        ZStack {
            // Live Playing RTSP Video Stream (內建單一連線 VLCKit 播放器)
            VLCVideoPlayer(rtspUrl: rtspUrl, viewModel: viewModel, cameraIndex: index)
            
            // Transparent SwiftUI Canvas Overlay (AI 人流綠框與人數)
            if isAiEnabled {
                LiveAIBoundingBoxCanvas(trackedHumans: liveHumans, count: liveCount)
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
    
    // MARK: - 內建 VLCKit 原生記憶體取樣 (完全擺脫外部 FFmpeg 依賴，零額外連線)
    private func updateAiStream() {
        stopAiStream()
        guard isAiEnabled else { return }
        
        AppLogger.log("🚀 [PlayerView \(index)] 啟動 VLCKit 內建記憶體 AI 畫面取樣 (10fps)")
        
        // 設定每 100ms (10fps) 取樣一張記憶體 Frame 送給 Vision / YOLO 深度學習分析
        aiSamplingTimer = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: true) { _ in
            guard isAiEnabled, !isAnalyzing else { return }
            
            // 優先取得 VLCKit 當前幀 (優先使用 lastSnapshot，備援使用 CALayer 記憶體渲染)
            var extractedFrame: NSImage? = nil
            
            if let snap = viewModel.mediaPlayer.lastSnapshot {
                extractedFrame = snap
            } else if let view = viewModel.containerView, let layer = view.layer {
                let width = Int(view.bounds.width)
                let height = Int(view.bounds.height)
                if width > 40 && height > 40 {
                    let colorSpace = CGColorSpaceCreateDeviceRGB()
                    if let context = CGContext(
                        data: nil,
                        width: width,
                        height: height,
                        bitsPerComponent: 8,
                        bytesPerRow: width * 4,
                        space: colorSpace,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    ) {
                        layer.render(in: context)
                        if let cgImg = context.makeImage() {
                            extractedFrame = NSImage(cgImage: cgImg, size: view.bounds.size)
                        }
                    }
                }
            }
            
            guard let image = extractedFrame else { return }
            self.isAnalyzing = true
            
            PeopleCounterService.shared.analyzePeopleCount(in: image, cameraIndex: self.index) { result in
                DispatchQueue.main.async {
                    if self.isAiEnabled {
                        self.liveHumans = result.trackedHumans
                        self.liveCount = result.count
                    }
                    self.isAnalyzing = false
                }
            }
        }
    }
    
    private func stopAiStream() {
        aiSamplingTimer?.invalidate()
        aiSamplingTimer = nil
        liveHumans = []
        liveCount = 0
        isAnalyzing = false
    }
}
