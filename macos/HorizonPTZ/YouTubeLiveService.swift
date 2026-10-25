import Foundation
import SwiftUI
import AuthenticationServices
import Security
import Network

struct YouTubeBroadcastItem: Identifiable, Equatable {
    let id: String
    let title: String
    let status: String // OFFLINE, TESTING, LIVE
    let liveChatId: String
    let boundStreamId: String?
    let scheduledStartTime: String?
}

struct YouTubeChatMessage: Identifiable, Equatable {
    let id: String
    let authorName: String
    let authorAvatarUrl: String
    let messageText: String
    let publishedAt: String
    let isChatOwner: Bool
    let isChatSponsor: Bool
}

final class YouTubeLiveService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = YouTubeLiveService()
    
    @Published var isLoggedIn: Bool = false
    @Published var channelTitle: String = "未連線帳號"
    @Published var channelAvatarUrl: String = ""
    @Published var subscriberCount: String = "0"
    
    @Published var currentBroadcastTitle: String = "主日禮拜 / 活動現場直播"
    @Published var currentBroadcastStatus: String = "OFFLINE" // OFFLINE, TESTING, LIVE
    @Published var streamKey: String = "live_stream_key_sample_12345"
    @Published var rtmpUrl: String = "rtmp://a.rtmp.youtube.com/live2"
    
    @Published var activeViewerCount: String = "0"
    @Published var likeCount: String = "0"
    @Published var currentBroadcastId: String = ""
    @Published var activeLiveChatId: String = ""
    @Published var chatMessages: [YouTubeChatMessage] = []
    @Published var isFetchingLive: Bool = false
    
    // 多直播場次支援
    @Published var availableBroadcasts: [YouTubeBroadcastItem] = []
    private var statsTimer: Timer? = nil
    private var chatTimer: Timer? = nil
    
    // 預設金鑰欄位（原始碼中不包含硬編碼明文憑證，初次使用請於「設定」輸入或由本機 UserDefaults 載入）
    static let defaultClientID = ""
    static let defaultClientSecret = ""
    
    @Published var clientID: String = UserDefaults.standard.string(forKey: "yt_client_id") ?? defaultClientID
    @Published var clientSecret: String = UserDefaults.standard.string(forKey: "yt_client_secret") ?? defaultClientSecret
    
    private let keychainAccount = "com.horizon.horizonptz.yt_refresh_token"
    private var accessToken: String? = nil
    private var localAuthListener: NWListener? = nil
    private var localAuthConnection: NWConnection? = nil
    
    override private init() {
        super.init()
        loadCredentials()
        startLocalServerAlways()
    }
    
    // 長駐啟動本地 8080 伺服器，負責 OAuth 回呼與提供合法的 /embed/ 播放器容器
    func startLocalServerAlways() {
        if localAuthListener != nil { return }
        
        do {
            let tcpOptions = NWProtocolTCP.Options()
            let params = NWParameters(tls: nil, tcp: tcpOptions)
            params.allowLocalEndpointReuse = true
            
            guard let port = NWEndpoint.Port(rawValue: 8080) else { return }
            localAuthListener = try NWListener(using: params, on: port)
            
            localAuthListener?.newConnectionHandler = { [weak self] connection in
                self?.handleIncomingConnection(connection)
            }
            
            localAuthListener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    AppLogger.log("🌐 [Local Web Server] Listening on http://localhost:8080")
                case .failed(let err):
                    AppLogger.log("⚠️ [Local Web Server] Error: \(err)")
                default:
                    break
                }
            }
            
            localAuthListener?.start(queue: .main)
        } catch {
            AppLogger.log("⚠️ [Local Web Server] Failed to start: \(error)")
        }
    }
    
    private func handleIncomingConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] content, _, _, _ in
            guard let self = self, let content = content, let requestString = String(data: content, encoding: .utf8) else {
                connection.cancel()
                return
            }
            
            guard let firstLine = requestString.components(separatedBy: "\r\n").first,
                  let path = firstLine.components(separatedBy: " ").dropFirst().first else {
                connection.cancel()
                return
            }
            
            // 路由 1: OAuth Callback (GET /callback?code=...)
            if path.hasPrefix("/callback") {
                if let urlComponents = URLComponents(string: "http://localhost:8080" + path),
                   let code = urlComponents.queryItems?.first(where: { $0.name == "code" })?.value {
                    
                    let htmlSuccess = """
                    HTTP/1.1 200 OK\r
                    Content-Type: text/html; charset=utf-8\r
                    Connection: close\r
                    \r
                    <!DOCTYPE html>
                    <html>
                    <head><title>HorizonPTZ Google 授權成功</title><meta charset="utf-8"></head>
                    <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; display: flex; flex-direction: column; align-items: center; justify-content: center; height: 90vh; background-color: #1e1e24; color: #f0f0f0;">
                        <div style="background: #2b2b36; padding: 40px 60px; border-radius: 16px; box-shadow: 0 8px 32px rgba(0,0,0,0.4); text-align: center; max-width: 500px;">
                            <h1 style="color: #4cd964; margin-bottom: 12px; font-size: 28px;">🎉 授權驗證成功！</h1>
                            <p style="font-size: 16px; color: #cfcfd4; line-height: 1.6;">您的 Google 帳號已成功授權 HorizonPTZ。</p>
                            <p style="font-size: 14px; color: #8e8e93; margin-top: 20px;">您可以關閉此瀏覽器分頁，並返回 <strong>HorizonPTZ</strong> 繼續操作！</p>
                        </div>
                    </body>
                    </html>
                    """
                    if let res = htmlSuccess.data(using: .utf8) {
                        connection.send(content: res, completion: .contentProcessed({ _ in connection.cancel() }))
                    }
                    self.exchangeCodeForToken(code: code, redirectURI: "http://localhost:8080/callback") { _, _ in }
                } else {
                    connection.cancel()
                }
                return
            }
            
            // 路由 2: 純淨合法 Embed 容器 (GET /embed?v=VIDEO_ID)
            if path.hasPrefix("/embed") {
                let urlComponents = URLComponents(string: "http://localhost:8080" + path)
                let videoId = urlComponents?.queryItems?.first(where: { $0.name == "v" })?.value ?? self.currentBroadcastId
                
                let embedHtml = """
                HTTP/1.1 200 OK\r
                Content-Type: text/html; charset=utf-8\r
                Connection: close\r
                \r
                <!DOCTYPE html>
                <html>
                <head>
                    <meta charset="utf-8">
                    <meta name="viewport" content="width=device-width, initial-scale=1">
                    <style>
                        * { margin: 0; padding: 0; box-sizing: border-box; }
                        body, html { width: 100%; height: 100%; overflow: hidden; background: #000; }
                        iframe { width: 100vw; height: 100vh; border: none; }
                    </style>
                </head>
                <body>
                    <iframe 
                        src="https://www.youtube.com/embed/\(videoId)?autoplay=1&mute=1&playsinline=1&controls=1&modestbranding=1&rel=0&origin=http://localhost:8080" 
                        allow="autoplay; encrypted-media; picture-in-picture" 
                        allowfullscreen>
                    </iframe>
                </body>
                </html>
                """
                if let res = embedHtml.data(using: .utf8) {
                    connection.send(content: res, completion: .contentProcessed({ _ in connection.cancel() }))
                }
                return
            }
            
            connection.cancel()
        }
    }
    
    func loadCredentials() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let savedID = UserDefaults.standard.string(forKey: "yt_client_id") ?? ""
            let savedSecret = UserDefaults.standard.string(forKey: "yt_client_secret") ?? ""
            
            let id = savedID.isEmpty ? Self.defaultClientID : savedID
            let secret = savedSecret.isEmpty ? Self.defaultClientSecret : savedSecret
            
            let storedRefreshToken = self.readKeychain(account: self.keychainAccount)
            
            DispatchQueue.main.async {
                self.clientID = id
                self.clientSecret = secret
                
                if let stored = storedRefreshToken, !stored.isEmpty {
                    self.isLoggedIn = true
                    self.refreshAccessToken(refreshToken: stored)
                }
            }
        }
    }
    
    func saveClientCredentials(id: String, secret: String) {
        self.clientID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        self.clientSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(self.clientID, forKey: "yt_client_id")
        UserDefaults.standard.set(self.clientSecret, forKey: "yt_client_secret")
    }
    
    // MARK: - OAuth 2.0 Login
    func startOAuthLogin(completion: @escaping (Bool, String) -> Void) {
        guard !clientID.isEmpty else {
            completion(false, "請先在【參數設定】中填寫 Google Client ID！")
            return
        }
        
        let redirectURI = "http://localhost:8080/callback"
        let scope = "https://www.googleapis.com/auth/youtube.force-ssl"
        
        // 啟動本地 8080 端口 HTTP 伺服器，自動攔截瀏覽器回傳的 code
        startLocalAuthServer(completion: completion)
        
        let authUrlString = "https://accounts.google.com/o/oauth2/v2/auth?client_id=\(clientID)&redirect_uri=\(redirectURI)&response_type=code&scope=\(scope)&access_type=offline&prompt=consent"
        
        guard let url = URL(string: authUrlString) else {
            completion(false, "網址建立失敗")
            return
        }
        
        // 同時喚起 macOS 系統驗證或瀏覽器
        NSWorkspace.shared.open(url)
    }
    
    private func startLocalAuthServer(completion: @escaping (Bool, String) -> Void) {
        stopLocalAuthServer()
        
        do {
            let tcpOptions = NWProtocolTCP.Options()
            let params = NWParameters(tls: nil, tcp: tcpOptions)
            params.allowLocalEndpointReuse = true
            
            guard let port = NWEndpoint.Port(rawValue: 8080) else { return }
            localAuthListener = try NWListener(using: params, on: port)
            
            localAuthListener?.newConnectionHandler = { [weak self] connection in
                self?.handleIncomingAuthConnection(connection, completion: completion)
            }
            
            localAuthListener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    AppLogger.log("🌐 [OAuth Server] Local auth server listening on port 8080")
                case .failed(let err):
                    AppLogger.log("⚠️ [OAuth Server] Local server error: \(err)")
                default:
                    break
                }
            }
            
            localAuthListener?.start(queue: .main)
        } catch {
            AppLogger.log("⚠️ [OAuth Server] Failed to start NWListener: \(error)")
        }
    }
    
    private func handleIncomingAuthConnection(_ connection: NWConnection, completion: @escaping (Bool, String) -> Void) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] content, _, _, _ in
            guard let self = self, let content = content, let requestString = String(data: content, encoding: .utf8) else {
                connection.cancel()
                return
            }
            
            // 解析 GET /callback?code=... HTTP/1.1
            if let firstLine = requestString.components(separatedBy: "\r\n").first,
               let path = firstLine.components(separatedBy: " ").dropFirst().first,
               let urlComponents = URLComponents(string: "http://localhost:8080" + path),
               let code = urlComponents.queryItems?.first(where: { $0.name == "code" })?.value {
                
                // 回應瀏覽器漂亮的成功頁面
                let htmlSuccess = """
                HTTP/1.1 200 OK\r
                Content-Type: text/html; charset=utf-8\r
                Connection: close\r
                \r
                <!DOCTYPE html>
                <html>
                <head><title>HorizonPTZ Google 授權成功</title><meta charset="utf-8"></head>
                <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; display: flex; flex-direction: column; align-items: center; justify-content: center; height: 90vh; background-color: #1e1e24; color: #f0f0f0;">
                    <div style="background: #2b2b36; padding: 40px 60px; border-radius: 16px; box-shadow: 0 8px 32px rgba(0,0,0,0.4); text-align: center; max-width: 500px;">
                        <h1 style="color: #4cd964; margin-bottom: 12px; font-size: 28px;">🎉 授權驗證成功！</h1>
                        <p style="font-size: 16px; color: #cfcfd4; line-height: 1.6;">您的 Google 帳號已成功授權 HorizonPTZ。</p>
                        <p style="font-size: 14px; color: #8e8e93; margin-top: 20px;">您可以關閉此瀏覽器分頁，並返回 <strong>HorizonPTZ</strong> 繼續操作！</p>
                    </div>
                </body>
                </html>
                """
                
                if let responseData = htmlSuccess.data(using: .utf8) {
                    connection.send(content: responseData, completion: .contentProcessed({ _ in
                        connection.cancel()
                    }))
                }
                
                // 關閉監聽並交換 Token
                self.stopLocalAuthServer()
                self.exchangeCodeForToken(code: code, redirectURI: "http://localhost:8080/callback", completion: completion)
                
            } else {
                // 非 callback 請求
                connection.cancel()
            }
        }
    }
    
    private func stopLocalAuthServer() {
        localAuthListener?.cancel()
        localAuthListener = nil
    }
    
    private func exchangeCodeForToken(code: String, redirectURI: String, completion: @escaping (Bool, String) -> Void) {
        guard let tokenUrl = URL(string: "https://oauth2.googleapis.com/token") else { return }
        
        var request = URLRequest(url: tokenUrl)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyString = "client_id=\(clientID)&client_secret=\(clientSecret)&code=\(code)&grant_type=authorization_code&redirect_uri=\(redirectURI)"
        request.httpBody = bodyString.data(using: .utf8)
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async { completion(false, "Token 交換失敗") }
                return
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let refreshToken = json["refresh_token"] as? String {
                    self.saveKeychain(account: self.keychainAccount, value: refreshToken)
                }
                if let accessToken = json["access_token"] as? String {
                    self.accessToken = accessToken
                    DispatchQueue.main.async {
                        self.isLoggedIn = true
                        self.fetchChannelInfo()
                        completion(true, "登入成功！")
                    }
                } else {
                    DispatchQueue.main.async { completion(false, "Google 回傳錯誤: \(json["error_description"] ?? json)") }
                }
            }
        }.resume()
    }
    
    func refreshAccessToken(refreshToken: String) {
        guard let tokenUrl = URL(string: "https://oauth2.googleapis.com/token") else { return }
        
        var request = URLRequest(url: tokenUrl)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyString = "client_id=\(clientID)&client_secret=\(clientSecret)&refresh_token=\(refreshToken)&grant_type=refresh_token"
        request.httpBody = bodyString.data(using: .utf8)
        
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newAccessToken = json["access_token"] as? String else { return }
            
            DispatchQueue.main.async {
                self.accessToken = newAccessToken
                self.isLoggedIn = true
                self.fetchChannelInfo()
            }
        }.resume()
    }
    
    func logout() {
        statsTimer?.invalidate()
        statsTimer = nil
        chatTimer?.invalidate()
        chatTimer = nil
        deleteKeychain(account: keychainAccount)
        self.isLoggedIn = false
        self.accessToken = nil
        self.channelTitle = "未連線帳號"
        self.channelAvatarUrl = ""
        self.subscriberCount = "0"
        self.currentBroadcastStatus = "OFFLINE"
        self.currentBroadcastTitle = "主日禮拜 / 活動現場直播"
        self.currentBroadcastId = ""
        self.activeLiveChatId = ""
        self.chatMessages = []
        self.availableBroadcasts = []
        self.activeViewerCount = "0"
        self.likeCount = "0"
    }
    
    // MARK: - YouTube Data API Calls
    func fetchChannelInfo() {
        guard let accessToken = accessToken,
              let url = URL(string: "https://www.googleapis.com/youtube/v3/channels?part=snippet,statistics&mine=true") else { return }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]],
                  let firstChannel = items.first,
                  let snippet = firstChannel["snippet"] as? [String: Any] else { return }
            
            DispatchQueue.main.async {
                self.channelTitle = snippet["title"] as? String ?? "YouTube 頻道"
                if let thumbnails = snippet["thumbnails"] as? [String: Any],
                   let defaultThumb = thumbnails["default"] as? [String: Any],
                   let urlStr = defaultThumb["url"] as? String {
                    self.channelAvatarUrl = urlStr
                }
                if let stats = firstChannel["statistics"] as? [String: Any],
                   let subs = stats["subscriberCount"] as? String {
                    self.subscriberCount = subs
                }
                // 獲取目前頻道最新直播活動與推流金鑰
                self.fetchCurrentLiveBroadcast()
            }
        }.resume()
    }
    
    // MARK: - 查詢現有直播活動與串流金鑰
    func fetchCurrentLiveBroadcast(completion: ((Bool) -> Void)? = nil) {
        guard let accessToken = accessToken else {
            completion?(false)
            return
        }
        
        DispatchQueue.main.async { self.isFetchingLive = true }
        
        // 1. 查詢最近活躍的直播活動 (active, upcoming, all)
        guard let url = URL(string: "https://www.googleapis.com/youtube/v3/liveBroadcasts?part=snippet,status,contentDetails&broadcastType=all&mine=true&maxResults=10") else { return }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }
            defer { DispatchQueue.main.async { self.isFetchingLive = false } }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]], !items.isEmpty else {
                // 如果沒有直播，嘗試自動獲取頻道的預設推流金鑰 (Default Ingest Stream Key)
                self.fetchDefaultLiveStream(completion: completion)
                return
            }
            
            // 解析場次列表：過濾出「今日/即將進行/正在進行」的有效直播，排除數週以前已結束的舊歷史檔
            var parsedBroadcasts: [YouTubeBroadcastItem] = []
            let isoFormatter = ISO8601DateFormatter()
            let now = Date()
            let calendar = Calendar.current
            
            for item in items {
                let id = item["id"] as? String ?? ""
                let snippet = item["snippet"] as? [String: Any] ?? [:]
                let title = snippet["title"] as? String ?? "未命名直播活動"
                let liveChatId = snippet["liveChatId"] as? String ?? ""
                let statusDict = item["status"] as? [String: Any] ?? [:]
                let lifeCycle = statusDict["lifeCycleStatus"] as? String ?? "OFFLINE"
                let contentDetails = item["contentDetails"] as? [String: Any] ?? [:]
                let boundStreamId = contentDetails["boundStreamId"] as? String
                let scheduledStartTime = snippet["scheduledStartTime"] as? String
                
                var displayStatus = "OFFLINE"
                if lifeCycle == "live" {
                    displayStatus = "LIVE"
                } else if lifeCycle == "testing" || lifeCycle == "testStarting" {
                    displayStatus = "TESTING"
                }
                
                // 判斷是否為今天或進行中的直播 (若已完全結束 complete 且不是今天，則視為歷史存檔不列入當日切換標籤)
                var isRelevantForToday = false
                if displayStatus == "LIVE" || displayStatus == "TESTING" || lifeCycle == "ready" {
                    isRelevantForToday = true
                } else if let startTimeStr = scheduledStartTime, let startDate = isoFormatter.date(from: startTimeStr) {
                    // 如果排程時間是今天、未來、或在過去 24 小時內
                    let hoursDiff = abs(now.timeIntervalSince(startDate)) / 3600.0
                    if calendar.isDateInToday(startDate) || startDate > now || hoursDiff < 24.0 {
                        isRelevantForToday = true
                    }
                }
                
                if isRelevantForToday {
                    parsedBroadcasts.append(YouTubeBroadcastItem(
                        id: id,
                        title: title,
                        status: displayStatus,
                        liveChatId: liveChatId,
                        boundStreamId: boundStreamId,
                        scheduledStartTime: scheduledStartTime
                    ))
                }
            }
            
            // 如果過濾後為空，至少保留最近的第一筆（例如最新剛開的活動）
            if parsedBroadcasts.isEmpty, let firstItem = items.first {
                let id = firstItem["id"] as? String ?? ""
                let snippet = firstItem["snippet"] as? [String: Any] ?? [:]
                let title = snippet["title"] as? String ?? "未命名直播活動"
                let liveChatId = snippet["liveChatId"] as? String ?? ""
                let contentDetails = firstItem["contentDetails"] as? [String: Any] ?? [:]
                let boundStreamId = contentDetails["boundStreamId"] as? String
                parsedBroadcasts.append(YouTubeBroadcastItem(
                    id: id,
                    title: title,
                    status: "OFFLINE",
                    liveChatId: liveChatId,
                    boundStreamId: boundStreamId,
                    scheduledStartTime: nil
                ))
            }
            
            // 決定當前選中的場次：若現有選中依然在列表中則維持，否則選取正在直播或第一筆
            let targetBroadcast = parsedBroadcasts.first(where: { $0.id == self.currentBroadcastId })
                ?? parsedBroadcasts.first(where: { $0.status == "LIVE" || $0.status == "TESTING" })
                ?? parsedBroadcasts.first!
            
            DispatchQueue.main.async {
                self.availableBroadcasts = parsedBroadcasts
                self.selectBroadcast(targetBroadcast, completion: completion)
            }
        }.resume()
    }
    
    // 選取特定直播場次並加載其對應金鑰與聊天室
    func selectBroadcast(_ broadcast: YouTubeBroadcastItem, completion: ((Bool) -> Void)? = nil) {
        self.currentBroadcastId = broadcast.id
        self.currentBroadcastTitle = broadcast.title
        self.activeLiveChatId = broadcast.liveChatId
        self.currentBroadcastStatus = broadcast.status
        self.chatMessages = []
        
        // 啟動即時人數與點讚統計更新
        self.startStatsPolling()
        // 啟動即時聊天室輪詢
        if !broadcast.liveChatId.isEmpty {
            self.startChatPolling()
        }
        
        // 獲取綁定的 Stream Key
        if let boundStreamId = broadcast.boundStreamId, !boundStreamId.isEmpty {
            self.fetchStreamDetails(streamId: boundStreamId, completion: completion)
        } else {
            self.fetchDefaultLiveStream(completion: completion)
        }
    }
    
    // 獲取直播串流金鑰
    func fetchStreamDetails(streamId: String, completion: ((Bool) -> Void)? = nil) {
        guard let accessToken = accessToken,
              let url = URL(string: "https://www.googleapis.com/youtube/v3/liveStreams?part=snippet,cdn,status&id=\(streamId)") else { return }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self = self,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]],
                  let stream = items.first,
                  let cdn = stream["cdn"] as? [String: Any],
                  let ingestionInfo = cdn["ingestionInfo"] as? [String: Any] else {
                completion?(false)
                return
            }
            
            let rtmp = ingestionInfo["ingestionAddress"] as? String ?? "rtmp://a.rtmp.youtube.com/live2"
            let key = ingestionInfo["streamName"] as? String ?? ""
            
            DispatchQueue.main.async {
                self.rtmpUrl = rtmp
                if !key.isEmpty {
                    self.streamKey = key
                }
                completion?(true)
            }
        }.resume()
    }
    
    // 獲取預設的 Live Stream (若未手動綁定)
    func fetchDefaultLiveStream(completion: ((Bool) -> Void)? = nil) {
        guard let accessToken = accessToken,
              let url = URL(string: "https://www.googleapis.com/youtube/v3/liveStreams?part=snippet,cdn,status&mine=true&maxResults=5") else { return }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self = self,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]],
                  let stream = items.first,
                  let cdn = stream["cdn"] as? [String: Any],
                  let ingestionInfo = cdn["ingestionInfo"] as? [String: Any] else {
                completion?(false)
                return
            }
            
            let rtmp = ingestionInfo["ingestionAddress"] as? String ?? "rtmp://a.rtmp.youtube.com/live2"
            let key = ingestionInfo["streamName"] as? String ?? ""
            
            DispatchQueue.main.async {
                self.rtmpUrl = rtmp
                if !key.isEmpty {
                    self.streamKey = key
                }
                completion?(true)
            }
        }.resume()
    }
    
    // MARK: - 即時直播統計輪詢 (Viewer Count, Likes)
    func startStatsPolling() {
        statsTimer?.invalidate()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            self?.pollLiveVideoStats()
        }
        pollLiveVideoStats()
    }
    
    func pollLiveVideoStats() {
        guard let accessToken = accessToken, !currentBroadcastId.isEmpty,
              let url = URL(string: "https://www.googleapis.com/youtube/v3/videos?part=liveStreamingDetails,statistics&id=\(currentBroadcastId)") else { return }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self = self,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]],
                  let video = items.first else { return }
            
            let stats = video["statistics"] as? [String: Any] ?? [:]
            let liveDetails = video["liveStreamingDetails"] as? [String: Any] ?? [:]
            
            let viewers = liveDetails["concurrentViewers"] as? String ?? "0"
            let likes = stats["likeCount"] as? String ?? "0"
            
            DispatchQueue.main.async {
                self.activeViewerCount = viewers
                self.likeCount = likes
            }
        }.resume()
    }
    
    // MARK: - 即時聊天室 (Live Chat) 讀取與發送
    func startChatPolling() {
        chatTimer?.invalidate()
        chatTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: true) { [weak self] _ in
            self?.pollChatMessages()
        }
        pollChatMessages()
    }
    
    func pollChatMessages() {
        guard let accessToken = accessToken, !activeLiveChatId.isEmpty,
              let url = URL(string: "https://www.googleapis.com/youtube/v3/liveChat/messages?liveChatId=\(activeLiveChatId)&part=id,snippet,authorDetails&maxResults=50") else { return }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else { return }
            
            var parsedMessages: [YouTubeChatMessage] = []
            for item in items {
                let id = item["id"] as? String ?? UUID().uuidString
                let snippet = item["snippet"] as? [String: Any] ?? [:]
                let text = snippet["displayMessage"] as? String ?? ""
                let published = snippet["publishedAt"] as? String ?? ""
                
                let authorDetails = item["authorDetails"] as? [String: Any] ?? [:]
                let name = authorDetails["displayName"] as? String ?? "訪客"
                let avatar = authorDetails["profileImageUrl"] as? String ?? ""
                let isOwner = authorDetails["isChatOwner"] as? Bool ?? false
                let isSponsor = authorDetails["isChatSponsor"] as? Bool ?? false
                
                parsedMessages.append(YouTubeChatMessage(
                    id: id,
                    authorName: name,
                    authorAvatarUrl: avatar,
                    messageText: text,
                    publishedAt: published,
                    isChatOwner: isOwner,
                    isChatSponsor: isSponsor
                ))
            }
            
            DispatchQueue.main.async {
                self.chatMessages = parsedMessages
            }
        }.resume()
    }
    
    func sendChatMessage(text: String, completion: @escaping (Bool, String) -> Void) {
        guard let accessToken = accessToken, !activeLiveChatId.isEmpty else {
            completion(false, "目前沒有正在進行的直播聊天室")
            return
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(false, "訊息內容不能為空")
            return
        }
        
        guard let url = URL(string: "https://www.googleapis.com/youtube/v3/liveChat/messages?part=snippet") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "snippet": [
                "liveChatId": activeLiveChatId,
                "type": "textMessageEvent",
                "textMessageDetails": [
                    "messageText": text
                ]
            ]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let _ = json["id"] as? String {
                DispatchQueue.main.async {
                    completion(true, "訊息已送出！")
                    self?.pollChatMessages() // 立即刷新
                }
            } else {
                DispatchQueue.main.async {
                    completion(false, "送出失敗，請確認直播聊天室是否已開放")
                }
            }
        }.resume()
    }
    
    func createLiveBroadcast(title: String, description: String, completion: @escaping (Bool, String) -> Void) {
        guard let accessToken = accessToken,
              let url = URL(string: "https://www.googleapis.com/youtube/v3/liveBroadcasts?part=snippet,status,contentDetails") else {
            completion(false, "請先登入 YouTube 帳號")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let now = Date()
        let formatter = ISO8601DateFormatter()
        let startTime = formatter.string(from: now)
        
        let body: [String: Any] = [
            "snippet": [
                "title": title,
                "description": description,
                "scheduledStartTime": startTime
            ],
            "status": [
                "privacyStatus": "unlisted" // public, unlisted, private
            ]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let broadcastId = json["id"] as? String {
                
                // 成功建立廣播後，立即自動為此廣播建立並綁定專屬 Stream Key (liveBroadcasts/bind)
                self.bindNewStreamToBroadcast(broadcastId: broadcastId, title: title) { bindSuccess, bindMsg in
                    DispatchQueue.main.async {
                        self.currentBroadcastId = broadcastId
                        self.currentBroadcastTitle = title
                        self.currentBroadcastStatus = "TESTING"
                        self.fetchCurrentLiveBroadcast() // 刷新最新完整狀態
                        completion(true, "🎉 直播活動已建立並綁定串流金鑰！")
                    }
                }
            } else {
                var errDetail = "建立直播活動失敗"
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorDict = json["error"] as? [String: Any],
                   let msg = errorDict["message"] as? String {
                    errDetail = msg
                }
                DispatchQueue.main.async { completion(false, "YouTube 回應: \(errDetail)") }
            }
        }.resume()
    }
    
    // 為建立的廣播活動綁定或建立推流通道 (bind)
    private func bindNewStreamToBroadcast(broadcastId: String, title: String, completion: @escaping (Bool, String) -> Void) {
        guard let accessToken = accessToken else { return }
        
        // 1. 先建立一個 liveStream
        guard let streamUrl = URL(string: "https://www.googleapis.com/youtube/v3/liveStreams?part=snippet,cdn") else { return }
        var streamReq = URLRequest(url: streamUrl)
        streamReq.httpMethod = "POST"
        streamReq.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        streamReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let streamBody: [String: Any] = [
            "snippet": ["title": "\(title) - Stream"],
            "cdn": [
                "frameRate": "variable",
                "ingestionType": "rtmp",
                "resolution": "variable"
            ]
        ]
        streamReq.httpBody = try? JSONSerialization.data(withJSONObject: streamBody)
        
        URLSession.shared.dataTask(with: streamReq) { [weak self] data, _, _ in
            guard let self = self,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let streamId = json["id"] as? String else {
                completion(false, "無法建立推流碼")
                return
            }
            
            // 2. 呼叫 liveBroadcasts/bind
            guard let bindUrl = URL(string: "https://www.googleapis.com/youtube/v3/liveBroadcasts/bind?id=\(broadcastId)&streamId=\(streamId)&part=id,contentDetails") else { return }
            var bindReq = URLRequest(url: bindUrl)
            bindReq.httpMethod = "POST"
            bindReq.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            
            URLSession.shared.dataTask(with: bindReq) { [weak self] bindData, _, _ in
                // 獲取該 stream 的金鑰詳情
                self?.fetchStreamDetails(streamId: streamId) { _ in
                    completion(true, "綁定完成")
                }
            }.resume()
        }.resume()
    }
    
    // MARK: - YouTube 官方生命週期切換 (liveBroadcasts/transition)
    // 狀態包含：testing (測試), live (正式開播), complete (結束直播)
    func transitionBroadcast(status: String, completion: ((Bool, String) -> Void)? = nil) {
        guard let accessToken = accessToken, !currentBroadcastId.isEmpty else {
            DispatchQueue.main.async {
                self.currentBroadcastStatus = status
                completion?(false, "尚未綁定有效直播 ID")
            }
            return
        }
        
        let apiStatus: String
        switch status.uppercased() {
        case "LIVE":
            apiStatus = "live"
        case "TESTING":
            apiStatus = "testing"
        case "COMPLETE", "OFFLINE":
            apiStatus = "complete"
        default:
            apiStatus = status.lowercased()
        }
        
        guard let url = URL(string: "https://www.googleapis.com/youtube/v3/liveBroadcasts/transition?broadcastStatus=\(apiStatus)&id=\(currentBroadcastId)&part=status") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let statusObj = json["status"] as? [String: Any],
               let lifeCycle = statusObj["lifeCycleStatus"] as? String {
                
                DispatchQueue.main.async {
                    if lifeCycle == "live" {
                        self.currentBroadcastStatus = "LIVE"
                        completion?(true, "🚀 已成功向 YouTube 伺服器切換為【正式開播】！")
                    } else if lifeCycle == "complete" {
                        self.currentBroadcastStatus = "OFFLINE"
                        self.statsTimer?.invalidate()
                        self.statsTimer = nil
                        self.chatTimer?.invalidate()
                        self.chatTimer = nil
                        completion?(true, "🛑 YouTube 伺服器已正式結束並封存此場直播！")
                    } else {
                        self.currentBroadcastStatus = lifeCycle.uppercased()
                        completion?(true, "直播狀態已更新為: \(lifeCycle)")
                    }
                }
            } else {
                // 如果發生錯誤，檢查具體訊息
                var errMsg = "狀態切換失敗"
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorDict = json["error"] as? [String: Any],
                   let msg = errorDict["message"] as? String {
                    errMsg = msg
                }
                
                DispatchQueue.main.async {
                    // 若是 complete，UI 也配合標記
                    if apiStatus == "complete" {
                        self.currentBroadcastStatus = "OFFLINE"
                    }
                    completion?(false, "YouTube API 回應: \(errMsg)")
                }
            }
        }.resume()
    }
    
    // MARK: - ASWebAuthenticationPresentationContextProviding
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
    
    // MARK: - Keychain Helper Functions
    private func saveKeychain(account: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    private func readKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        if status == errSecSuccess, let data = dataTypeRef as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
    
    private func deleteKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
