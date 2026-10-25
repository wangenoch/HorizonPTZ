import Foundation

class CameraRepository {
    static let shared = CameraRepository()
    
    private let defaults = UserDefaults.standard
    
    func saveConfig(index: Int, config: CameraConfig) {
        if let encoded = try? JSONEncoder().encode(config) {
            defaults.set(encoded, forKey: "cam_\(index)_config")
        }
    }
    
    func getConfig(index: Int) -> CameraConfig {
        if let data = defaults.data(forKey: "cam_\(index)_config"),
           let config = try? JSONDecoder().decode(CameraConfig.self, from: data) {
            return config
        }
        
        // Return default configurations matching Android app
        let defaultIp = (index == 1) ? "192.168.5.153" : "192.168.5.163"
        return CameraConfig(
            ipAddress: defaultIp,
            camName: "CAM 0\(index)"
        )
    }
    
    func isVirtualJoystickEnabled() -> Bool {
        return defaults.object(forKey: "virtual_joystick_enabled") as? Bool ?? true
    }
    
    func setVirtualJoystickEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: "virtual_joystick_enabled")
    }
    
    func getMouseDragPtzMode() -> MouseDragPtzMode {
        let raw = defaults.string(forKey: "mouse_drag_ptz_mode") ?? MouseDragPtzMode.vector.rawValue
        return MouseDragPtzMode(rawValue: raw) ?? .vector
    }
    
    func setMouseDragPtzMode(_ mode: MouseDragPtzMode) {
        defaults.set(mode.rawValue, forKey: "mouse_drag_ptz_mode")
    }
    
    func getExpoStrength() -> Float {
        return defaults.float(forKey: "expo_strength") == 0 ? 2.0 : defaults.float(forKey: "expo_strength")
    }
    
    func setExpoStrength(_ strength: Float) {
        defaults.set(strength, forKey: "expo_strength")
    }
    
    func getSensitivity(index: Int) -> Double {
        let val = defaults.double(forKey: "cam_\(index)_sensitivity")
        return val == 0 ? 1.0 : val
    }
    
    func setSensitivity(index: Int, value: Double) {
        defaults.set(value, forKey: "cam_\(index)_sensitivity")
    }
    
    func getSwitcherIp() -> String {
        return defaults.string(forKey: "switcher_ip") ?? "192.168.5.99"
    }
    
    func setSwitcherIp(_ ip: String) {
        defaults.set(ip, forKey: "switcher_ip")
    }
    
    func getYoutubeChannelId() -> String {
        return defaults.string(forKey: "youtube_channel_id") ?? "UCrkMMKcu78UNdcthAMOL-tA"
    }
    
    func setYoutubeChannelId(_ id: String) {
        defaults.set(id, forKey: "youtube_channel_id")
    }
    
    func getYoutubeStreamKey() -> String {
        return defaults.string(forKey: "youtube_stream_key") ?? "u7ug-xjxv-vkk4-5mtm-6xbk"
    }
    
    func setYoutubeStreamKey(_ key: String) {
        defaults.set(key, forKey: "youtube_stream_key")
    }
    
    func getYoutubeUrl() -> String {
        let channelId = getYoutubeChannelId().trimmingCharacters(in: .whitespacesAndNewlines)
        if channelId.isEmpty {
            return "https://studio.youtube.com/"
        } else {
            return "https://studio.youtube.com/channel/\(channelId)"
        }
    }
    
    func getSwitcherLayoutMode() -> SwitcherLayoutMode {
        if let raw = defaults.string(forKey: "switcher_layout_mode"),
           let mode = SwitcherLayoutMode(rawValue: raw) {
            return mode
        }
        return .bottomConsole
    }
    
    func setSwitcherLayoutMode(_ mode: SwitcherLayoutMode) {
        defaults.set(mode.rawValue, forKey: "switcher_layout_mode")
    }
    
    // MARK: - Unified App Settings
    func getAppSettings() -> AppSettings {
        if let data = defaults.data(forKey: "app_settings"),
           let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            return settings
        }
        return AppSettings(
            switcherIp: getSwitcherIp(),
            switcherLayoutMode: getSwitcherLayoutMode(),
            youtubeChannelId: getYoutubeChannelId(),
            youtubeStreamKey: getYoutubeStreamKey(),
            expoStrength: getExpoStrength(),
            virtualJoystickEnabled: isVirtualJoystickEnabled()
        )
    }
    
    func saveAppSettings(_ settings: AppSettings) {
        if let encoded = try? JSONEncoder().encode(settings) {
            defaults.set(encoded, forKey: "app_settings")
        }
        // Keep legacy keys synchronized for backward compatibility
        setSwitcherIp(settings.switcherIp)
        setSwitcherLayoutMode(settings.switcherLayoutMode)
        setYoutubeChannelId(settings.youtubeChannelId)
        setYoutubeStreamKey(settings.youtubeStreamKey)
        setExpoStrength(settings.expoStrength)
        setVirtualJoystickEnabled(settings.virtualJoystickEnabled)
    }
    
    // MARK: - AI Settings Persistence
    func getAiSettings() -> AiSettings {
        if let data = defaults.data(forKey: "ai_settings"),
           let settings = try? JSONDecoder().decode(AiSettings.self, from: data) {
            return settings
        }
        return AiSettings()
    }
    
    func saveAiSettings(_ settings: AiSettings) {
        if let encoded = try? JSONEncoder().encode(settings) {
            defaults.set(encoded, forKey: "ai_settings")
        }
    }
}

enum SwitcherLayoutMode: String, CaseIterable, Identifiable, Codable {
    case bottomConsole = "底部廣播控制台"
    case rightSidebar = "右側直立導播欄"
    case floatingWindow = "獨立懸浮導播窗"
    case embeddedSlot = "單槽子母預覽"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .bottomConsole: return "rectangle.bottomthird.inset.filled"
        case .rightSidebar: return "sidebar.right"
        case .floatingWindow: return "macwindow.on.rectangle"
        case .embeddedSlot: return "rectangle.on.rectangle"
        }
    }
}

enum MouseDragPtzMode: String, CaseIterable, Identifiable, Codable {
    case vector = "vector"
    case canvasGrab = "canvasGrab"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .vector: return "向量式"
        case .canvasGrab: return "抓取式"
        }
    }
    
    var icon: String {
        switch self {
        case .vector: return "arrow.up.right"
        case .canvasGrab: return "hand.draw"
        }
    }
    
    var helpText: String {
        switch self {
        case .vector: return "向量模式：按住滑鼠拉出箭頭，拉的方向為旋轉方向，拉的距離決定速度（拉越遠越快）"
        case .canvasGrab: return "抓取模式：像地圖抓取畫布平移，即時跟隨滑鼠拖曳移動鏡頭"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var switcherIp: String = "192.168.5.99"
    var switcherLayoutMode: SwitcherLayoutMode = .bottomConsole
    var youtubeChannelId: String = "UCrkMMKcu78UNdcthAMOL-tA"
    var youtubeStreamKey: String = "u7ug-xjxv-vkk4-5mtm-6xbk"
    var expoStrength: Float = 2.0
    var virtualJoystickEnabled: Bool = true
    var mouseDragPtzMode: MouseDragPtzMode = .vector
}
