import Foundation

struct CameraConfig: Codable, Equatable {
    var ipAddress: String
    var controlPort: Int = 52381
    var rtspPort: Int = 554
    var rtspPath: String = "/live/av1"
    var account: String = "admin"
    var password: String = "admin"
    var camName: String = "Camera"
    var useTcp: Bool = true
    var protocolType: String = "VISCA/UDP"
    var showPort: Bool = false
    var autoConnect: Bool = true
    var engine: String = "ffmpeg"
    
    var rtspUrl: String {
        let portSuffix = showPort ? ":\(rtspPort)" : ""
        let pathPrefix = rtspPath.hasPrefix("/") ? "" : "/"
        return "rtsp://\(account):\(password)@\(ipAddress)\(portSuffix)\(pathPrefix)\(rtspPath)"
    }
}
