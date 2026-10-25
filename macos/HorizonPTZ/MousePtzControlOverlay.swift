import SwiftUI
import AppKit

struct MousePtzControlOverlay: View {
    let cameraIndex: Int
    let client: ViscaClient?
    let sensitivity: Double
    let dragMode: MouseDragPtzMode
    let onToggleMode: () -> Void
    let onShowController: () -> Void
    
    // Vector drag state
    @State private var dragAnchor: CGPoint? = nil
    @State private var dragCurrent: CGPoint? = nil
    @State private var activePanSpeed: Int = 0
    @State private var activeTiltSpeed: Int = 0
    @State private var activePanDir: String = ""
    @State private var activeTiltDir: String = ""
    
    // Canvas grab state
    @State private var grabPrevious: CGPoint? = nil
    @State private var grabCurrent: CGPoint? = nil
    @State private var isGrabbing: Bool = false
    @State private var grabStopTimer: Timer? = nil
    
    // Throttling & Hover
    @State private var lastCommandTime: Date = Date.distantPast
    @State private var isHovered: Bool = false
    @State private var zoomFeedbackText: String? = nil
    @State private var zoomFeedbackTimer: Timer? = nil
    @State private var zoomStopTimer: Timer? = nil
    @State private var eventMonitor: Any? = nil
    
    // Max vector drag radius
    private let vectorRadius: CGFloat = 85.0
    
    var body: some View {
        ZStack {
            // Interactive Gesture Surface
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .local)
                        .onChanged { value in
                            switch dragMode {
                            case .vector:
                                handleVectorDragChanged(value: value)
                            case .canvasGrab:
                                handleGrabDragChanged(value: value)
                            }
                        }
                        .onEnded { _ in
                            switch dragMode {
                            case .vector:
                                handleVectorDragEnded()
                            case .canvasGrab:
                                handleGrabDragEnded()
                            }
                        }
                )
                .onHover { hovering in
                    isHovered = hovering
                    updateCursor(hovering: hovering)
                }
                
                // Vector Mode Visual Overlay
                if dragMode == .vector, let anchor = dragAnchor, let current = dragCurrent {
                    renderVectorVisual(anchor: anchor, current: current)
                }
                
                // Canvas Grab Visual Overlay
                if dragMode == .canvasGrab, isGrabbing, let grabPt = grabCurrent {
                    renderGrabVisual(point: grabPt)
                }
                
                // Zoom Feedback Toast (滾輪縮放回饋)
                if let text = zoomFeedbackText {
                    VStack {
                        Spacer()
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12, weight: .bold))
                            Text(text)
                                .font(.system(size: 11, weight: .bold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.85))
                        .foregroundColor(.yellow)
                        .cornerRadius(12)
                        .shadow(radius: 4)
                        .padding(.bottom, 24)
                    }
                    .transition(.opacity)
                }
                
                // Top-Right Floating Control Pill (縮小精緻化，下移避免遮擋頂部相機/網頁標籤)
                VStack {
                    HStack {
                        Spacer()
                        
                        HStack(spacing: 4) {
                            // Mode Switch Button (向量式 / 抓取式)
                            Button(action: {
                                onToggleMode()
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: dragMode.icon)
                                        .font(.system(size: 9, weight: .bold))
                                    Text(dragMode.title)
                                        .font(.system(size: 9.5, weight: .bold))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.blue.opacity(0.85))
                                .foregroundColor(.white)
                                .cornerRadius(5)
                            }
                            .buttonStyle(.plain)
                            .help(dragMode.helpText + "（點此切換模式）")
                            
                            // Restore Controller Button
                            Button(action: {
                                onShowController()
                            }) {
                                HStack(spacing: 2) {
                                    Image(systemName: "gamecontroller")
                                        .font(.system(size: 9))
                                    Text("控制器")
                                        .font(.system(size: 9, weight: .semibold))
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 3)
                                .background(Color.black.opacity(0.65))
                                .foregroundColor(.white.opacity(0.9))
                                .cornerRadius(5)
                            }
                            .buttonStyle(.plain)
                            .help("恢復右下角虛擬 PTZ 搖桿盤")
                        }
                        .padding(4)
                        .background(Color.black.opacity(0.55))
                        .cornerRadius(6)
                        .padding(.top, 42) // 避開頂部的 [相機 | 網頁 | 導播機] 標籤
                        .padding(.trailing, 8)
                        .opacity(isHovered || dragAnchor != nil || isGrabbing ? 1.0 : 0.75)
                    }
                    
                    Spacer()
                }
            }
            .onAppear {
                setupScrollWheelMonitoring()
            }
            .onDisappear {
                removeScrollWheelMonitoring()
                handleEmergencyStop()
            }
        }
    
    // MARK: - Vector Mode Logic
    
    private func handleVectorDragChanged(value: DragGesture.Value) {
        let anchor = dragAnchor ?? value.startLocation
        dragAnchor = anchor
        let current = value.location
        dragCurrent = current
        
        let dx = current.x - anchor.x
        let dy = current.y - anchor.y
        let distance = hypot(dx, dy)
        
        // Deadzone check
        if distance < 8.0 {
            activePanSpeed = 0
            activeTiltSpeed = 0
            activePanDir = ""
            activeTiltDir = ""
            sendPtzThrottled(panSpeed: 0, tiltSpeed: 0, panMode: 0, tiltMode: 0)
            return
        }
        
        let ratioX = min(1.0, abs(dx) / vectorRadius)
        let ratioY = min(1.0, abs(dy) / vectorRadius)
        
        let speedFactor = CGFloat(sensitivity)
        let panSpeed = max(1, min(24, Int(ratioX * 24.0 * speedFactor)))
        let tiltSpeed = max(1, min(20, Int(ratioY * 20.0 * speedFactor)))
        
        // Screen coords: X right is +, left is -; Y down is +, up is -
        let panMode: Int
        if dx > 6.0 {
            panMode = 2 // Right
            activePanDir = "右"
        } else if dx < -6.0 {
            panMode = 1 // Left
            activePanDir = "左"
        } else {
            panMode = 0
            activePanDir = ""
        }
        
        let tiltMode: Int
        if dy < -6.0 {
            tiltMode = 1 // Up
            activeTiltDir = "上"
        } else if dy > 6.0 {
            tiltMode = 2 // Down
            activeTiltDir = "下"
        } else {
            tiltMode = 0
            activeTiltDir = ""
        }
        
        activePanSpeed = (panMode != 0) ? panSpeed : 0
        activeTiltSpeed = (tiltMode != 0) ? tiltSpeed : 0
        
        sendPtzThrottled(panSpeed: panSpeed, tiltSpeed: tiltSpeed, panMode: panMode, tiltMode: tiltMode)
    }
    
    private func handleVectorDragEnded() {
        dragAnchor = nil
        dragCurrent = nil
        activePanSpeed = 0
        activeTiltSpeed = 0
        activePanDir = ""
        activeTiltDir = ""
        client?.sendPtzCommand(panSpeed: 0, tiltSpeed: 0, panMode: 0, tiltMode: 0)
    }
    
    // MARK: - Canvas Grab Mode Logic
    
    private func handleGrabDragChanged(value: DragGesture.Value) {
        let prev = grabPrevious ?? value.startLocation
        let cur = value.location
        let dx = cur.x - prev.x
        let dy = cur.y - prev.y
        
        grabPrevious = cur
        grabCurrent = cur
        isGrabbing = true
        
        let speedFactor = CGFloat(sensitivity)
        let panSpeed = max(1, min(24, Int(min(1.0, abs(dx) / 14.0) * 24.0 * speedFactor)))
        let tiltSpeed = max(1, min(20, Int(min(1.0, abs(dy) / 12.0) * 20.0 * speedFactor)))
        
        // Grab logic: dragging left steers camera left; dragging right steers camera right
        let panMode = dx > 1.5 ? 2 : (dx < -1.5 ? 1 : 0)
        let tiltMode = dy < -1.5 ? 1 : (dy > 1.5 ? 2 : 0)
        
        sendPtzThrottled(panSpeed: panSpeed, tiltSpeed: tiltSpeed, panMode: panMode, tiltMode: tiltMode)
        
        // Reset auto-stop timer: If mouse stops moving while held down, stop camera motion smoothly
        grabStopTimer?.invalidate()
        grabStopTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) { [weak client] _ in
            client?.sendPtzCommand(panSpeed: 0, tiltSpeed: 0, panMode: 0, tiltMode: 0)
        }
    }
    
    private func handleGrabDragEnded() {
        grabStopTimer?.invalidate()
        grabStopTimer = nil
        grabPrevious = nil
        grabCurrent = nil
        isGrabbing = false
        client?.sendPtzCommand(panSpeed: 0, tiltSpeed: 0, panMode: 0, tiltMode: 0)
    }
    
    // MARK: - Throttling Command Delivery
    
    private func sendPtzThrottled(panSpeed: Int, tiltSpeed: Int, panMode: Int, tiltMode: Int) {
        let now = Date()
        guard now.timeIntervalSince(lastCommandTime) >= 0.045 else { return }
        lastCommandTime = now
        client?.sendPtzCommand(panSpeed: panSpeed, tiltSpeed: tiltSpeed, panMode: panMode, tiltMode: tiltMode)
    }
    
    private func handleEmergencyStop() {
        grabStopTimer?.invalidate()
        grabStopTimer = nil
        client?.sendPtzCommand(panSpeed: 0, tiltSpeed: 0, panMode: 0, tiltMode: 0)
    }
    
    // MARK: - Visual Overlays
    
    @ViewBuilder
    private func renderVectorVisual(anchor: CGPoint, current: CGPoint) -> some View {
        let dx = current.x - anchor.x
        let dy = current.y - anchor.y
        let distance = hypot(dx, dy)
        let isMoving = distance >= 8.0
        
        ZStack {
            // Anchor Center Circle
            Circle()
                .stroke(isMoving ? Color.cyan : Color.white.opacity(0.6), lineWidth: 2)
                .background(Circle().fill(Color.cyan.opacity(0.18)))
                .frame(width: 28, height: 28)
                .position(anchor)
            
            // Maximum speed range dashed boundary
            Circle()
                .stroke(
                    Color.cyan.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])
                )
                .frame(width: vectorRadius * 2, height: vectorRadius * 2)
                .position(anchor)
            
            // Dynamic Vector Arrow Line
            if isMoving {
                Path { path in
                    path.move(to: anchor)
                    path.addLine(to: current)
                }
                .stroke(
                    LinearGradient(
                        colors: [Color.cyan.opacity(0.5), Color.cyan, Color.white],
                        startPoint: .init(x: anchor.x / 1000, y: anchor.y / 1000),
                        endPoint: .init(x: current.x / 1000, y: current.y / 1000)
                    ),
                    style: StrokeStyle(lineWidth: 3.0, lineCap: .round)
                )
                
                // Cursor Head Dot with Direction & Speed Badge
                VStack(spacing: 2) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                        .shadow(color: Color.cyan, radius: 4)
                    
                    HStack(spacing: 3) {
                        Text("\(activePanDir)\(activePanSpeed)")
                        if !activeTiltDir.isEmpty {
                            Text("\(activeTiltDir)\(activeTiltSpeed)")
                        }
                    }
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.8))
                    .foregroundColor(.cyan)
                    .cornerRadius(4)
                }
                .position(current)
            }
        }
        .allowsHitTesting(false)
    }
    
    @ViewBuilder
    private func renderGrabVisual(point: CGPoint) -> some View {
        ZStack {
            Circle()
                .stroke(Color.green.opacity(0.7), lineWidth: 2)
                .background(Circle().fill(Color.green.opacity(0.2)))
                .frame(width: 38, height: 38)
            
            Image(systemName: "hand.draw.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
        }
        .position(point)
        .allowsHitTesting(false)
    }
    
    // MARK: - Cursor Management
    
    private func updateCursor(hovering: Bool) {
        if hovering {
            switch dragMode {
            case .vector:
                NSCursor.crosshair.push()
            case .canvasGrab:
                NSCursor.openHand.push()
            }
        } else {
            NSCursor.pop()
        }
    }
    
    // MARK: - Scroll Wheel Zoom Monitoring (滑鼠滾輪變焦)
    
    private func setupScrollWheelMonitoring() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak client] event in
            // Only trigger zoom when cursor is hovering over this camera view
            guard isHovered else { return event }
            
            // Check deltaY threshold
            let deltaY = event.scrollingDeltaY
            if abs(deltaY) > 0.8 {
                if deltaY > 0 {
                    // Scroll Up -> Zoom In
                    client?.sendZoomCommand(mode: 1, speed: 4)
                    showZoomToast(text: "放大 (Zoom In)")
                } else {
                    // Scroll Down -> Zoom Out
                    client?.sendZoomCommand(mode: 2, speed: 4)
                    showZoomToast(text: "縮小 (Zoom Out)")
                }
                
                zoomStopTimer?.invalidate()
                zoomStopTimer = Timer.scheduledTimer(withTimeInterval: 0.22, repeats: false) { _ in
                    client?.sendZoomCommand(mode: 0, speed: 0)
                }
            }
            return event
        }
    }
    
    private func removeScrollWheelMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        zoomStopTimer?.invalidate()
        zoomStopTimer = nil
        zoomFeedbackTimer?.invalidate()
        zoomFeedbackTimer = nil
    }
    
    private func showZoomToast(text: String) {
        withAnimation(.easeOut(duration: 0.15)) {
            zoomFeedbackText = text
        }
        zoomFeedbackTimer?.invalidate()
        zoomFeedbackTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { _ in
            withAnimation(.easeIn(duration: 0.2)) {
                zoomFeedbackText = nil
            }
        }
    }
}
