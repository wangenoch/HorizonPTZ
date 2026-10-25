import AppKit
import SwiftUI

final class LiveMonitorWindowController: NSObject, NSWindowDelegate, ObservableObject {
    static let shared = LiveMonitorWindowController()
    
    // 支援每個 broadcastId 獨立視窗字典
    private var windows: [String: NSWindow] = [:]
    @Published var openWindowIds: Set<String> = []
    @Published var isFloating: Bool = false
    
    private override init() {
        super.init()
    }
    
    func isWindowOpen(broadcastId: String) -> Bool {
        return openWindowIds.contains(broadcastId)
    }
    
    func showWindow(broadcastId: String, title: String? = nil) {
        let targetId = broadcastId.isEmpty ? "default" : broadcastId
        
        if let existing = windows[targetId] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            openWindowIds.insert(targetId)
            isFloating = true
            return
        }
        
        let initialWidth: CGFloat = 840
        let initialHeight: CGFloat = 500
        
        let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 100, y: 100, width: 1280, height: 720)
        let offset = CGFloat(windows.count * 30)
        let originX = screenRect.midX - initialWidth / 2 + offset
        let originY = screenRect.midY - initialHeight / 2 - offset
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: originX, y: originY, width: initialWidth, height: initialHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        let displayTitle = title ?? "直播即時畫面監看"
        newWindow.title = "HorizonPTZ - \(displayTitle) (獨立置頂)"
        newWindow.minSize = NSSize(width: 440, height: 260)
        newWindow.isReleasedWhenClosed = false
        newWindow.level = .floating // 永遠置頂
        newWindow.collectionBehavior = [.fullScreenPrimary, .managed]
        newWindow.delegate = self
        
        let rootView = FloatingLiveMonitorContainerView(broadcastId: targetId, windowTitle: displayTitle)
        newWindow.contentViewController = NSHostingController(rootView: rootView)
        
        windows[targetId] = newWindow
        openWindowIds.insert(targetId)
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.isFloating = true
    }
    
    func closeWindow(broadcastId: String? = nil) {
        if let bId = broadcastId {
            let targetId = bId.isEmpty ? "default" : bId
            windows[targetId]?.orderOut(nil)
            windows.removeValue(forKey: targetId)
            openWindowIds.remove(targetId)
        } else {
            // 關閉所有視窗
            for (_, win) in windows {
                win.orderOut(nil)
            }
            windows.removeAll()
            openWindowIds.removeAll()
        }
        isFloating = !openWindowIds.isEmpty
    }
    
    func toggleWindow(broadcastId: String, title: String? = nil) {
        let targetId = broadcastId.isEmpty ? "default" : broadcastId
        if isWindowOpen(broadcastId: targetId) {
            closeWindow(broadcastId: targetId)
        } else {
            showWindow(broadcastId: targetId, title: title)
        }
    }
    
    // MARK: - NSWindowDelegate
    func windowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow else { return }
        for (id, win) in windows where win == closedWindow {
            windows.removeValue(forKey: id)
            openWindowIds.remove(id)
            break
        }
        DispatchQueue.main.async {
            self.isFloating = !self.openWindowIds.isEmpty
        }
    }
}

struct FloatingLiveMonitorContainerView: View {
    let broadcastId: String
    let windowTitle: String
    @ObservedObject private var monitorCtrl = LiveMonitorWindowController.shared
    @ObservedObject private var ytService = YouTubeLiveService.shared
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            
            let actualId = (broadcastId == "default") ? ytService.currentBroadcastId : broadcastId
            
            if !actualId.isEmpty {
                WebBrowserComponent(
                    initialUrl: "http://localhost:8080/embed?v=\(actualId)",
                    showToolbar: false
                )
                .ignoresSafeArea()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "video.slash.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.gray)
                    Text("目前尚無活躍的直播串流")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }
            }
            
            // 懸浮標籤與關閉按鈕
            HStack(spacing: 8) {
                Text(windowTitle)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.75))
                    .cornerRadius(6)
                
                Button(action: {
                    monitorCtrl.closeWindow(broadcastId: broadcastId)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                        Text("關閉視窗")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.85))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
        }
    }
}
