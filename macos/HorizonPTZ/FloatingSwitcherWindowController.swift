import AppKit
import SwiftUI

final class FloatingSwitcherWindowController: NSObject, NSWindowDelegate, ObservableObject {
    static let shared = FloatingSwitcherWindowController()
    
    private var window: NSWindow?
    @Published var isVisible: Bool = false
    
    private override init() {
        super.init()
    }
    
    func showWindow() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            isVisible = true
            return
        }
        
        let initialWidth: CGFloat = 620
        let initialHeight: CGFloat = 380
        
        // Center on main screen or active screen
        let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 100, y: 100, width: 1200, height: 800)
        let originX = screenRect.midX - initialWidth / 2
        let originY = screenRect.midY - initialHeight / 2
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: originX, y: originY, width: initialWidth, height: initialHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.title = "HorizonPTZ - 導播機控制台 (獨立視窗)"
        newWindow.minSize = NSSize(width: 500, height: 320)
        newWindow.isReleasedWhenClosed = false
        newWindow.level = .floating // Stay on top for easy live switching or secondary display
        newWindow.delegate = self
        
        let rootView = SwitcherControlView(layoutStyle: .floating)
        newWindow.contentViewController = NSHostingController(rootView: rootView)
        
        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        isVisible = true
    }
    
    func closeWindow() {
        window?.orderOut(nil)
        isVisible = false
    }
    
    func toggleWindow() {
        if isVisible {
            closeWindow()
        } else {
            showWindow()
        }
    }
    
    // MARK: - NSWindowDelegate
    func windowWillClose(_ notification: Notification) {
        isVisible = false
    }
}
