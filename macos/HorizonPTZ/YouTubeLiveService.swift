import Foundation
import SwiftUI
import AuthenticationServices
import Security

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
    
    @Published var clientID: String = UserDefaults.standard.string(forKey: "yt_client_id") ?? ""
    @Published var clientSecret: String = UserDefaults.standard.string(forKey: "yt_client_secret") ?? ""
    
    private let keychainAccount = "com.horizon.horizonptz.yt_refresh_token"
    private var accessToken: String? = nil
    
    override private init() {
        super.init()
        loadCredentials()
    }
    
    func loadCredentials() {
        self.clientID = UserDefaults.standard.string(forKey: "yt_client_id") ?? ""
        self.clientSecret = UserDefaults.standard.string(forKey: "yt_client_secret") ?? ""
        
        if let storedRefreshToken = readKeychain(account: keychainAccount), !storedRefreshToken.isEmpty {
            self.isLoggedIn = true
            refreshAccessToken(refreshToken: storedRefreshToken)
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
        
        let authUrlString = "https://accounts.google.com/o/oauth2/v2/auth?client_id=\(clientID)&redirect_uri=\(redirectURI)&response_type=code&scope=\(scope)&access_type=offline&prompt=consent"
        
        guard let url = URL(string: authUrlString) else {
            completion(false, "網址建立失敗")
            return
        }
        
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "http") { callbackURL, error in
            if let error = error {
                completion(false, "授權取消或失敗: \(error.localizedDescription)")
                return
            }
            
            guard let callbackURL = callbackURL,
                  let components = URLComponents(string: callbackURL.absoluteString),
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                completion(false, "未取得授權碼 (Code)")
                return
            }
            
            self.exchangeCodeForToken(code: code, redirectURI: redirectURI, completion: completion)
        }
        
        session.presentationContextProvider = self
        session.start()
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
        deleteKeychain(account: keychainAccount)
        self.isLoggedIn = false
        self.accessToken = nil
        self.channelTitle = "未連線帳號"
        self.channelAvatarUrl = ""
        self.subscriberCount = "0"
        self.currentBroadcastStatus = "OFFLINE"
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
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let broadcastId = json["id"] as? String {
                DispatchQueue.main.async {
                    self.currentBroadcastTitle = title
                    self.currentBroadcastStatus = "TESTING"
                    completion(true, "直播活動建立成功 (ID: \(broadcastId))")
                }
            } else {
                DispatchQueue.main.async { completion(false, "建立直播活動失敗") }
            }
        }.resume()
    }
    
    func transitionBroadcast(status: String) {
        DispatchQueue.main.async {
            self.currentBroadcastStatus = status
        }
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
