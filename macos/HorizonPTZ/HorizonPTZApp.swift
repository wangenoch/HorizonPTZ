import SwiftUI

@main
struct HorizonPTZApp: App {
    init() {
        // Disable WebKit GPU Process to prevent graphics rendering crashes on older Intel Macs
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: "WebKitGPUProcessForCanvasRenderingEnabled")
        defaults.set(false, forKey: "WebKitGPUProcessForDOMRenderingEnabled")
        defaults.set(false, forKey: "WebKitGPUProcessForWebGLInterfaceEnabled")
        defaults.set(false, forKey: "WebKitGPUProcessForMediaPlaybackEnabled")
        defaults.set(false, forKey: "WebKitWebGL2Enabled")
        defaults.set(false, forKey: "WebKitWebGLEnabled")
        defaults.synchronize()
    }
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .navigationTitle("HorizonPTZ 控制中心")
        }
        .windowStyle(.titleBar)
    }
}
