import SwiftUI

struct YouTubeStudioDashboardView: View {
    @ObservedObject private var ytService = YouTubeLiveService.shared
    
    @State private var broadcastTitleInput: String = "主日禮拜 / 活動現場直播"
    @State private var broadcastDescInput: String = "HorizonPTZ AI 智慧雙鏡頭自動追蹤串流直播"
    @State private var statusMessage: String = ""
    @State private var isShowingStatusMessage: Bool = false
    
    @State private var showWebMonitor: Bool = false
    @State private var webMonitorUrl: String = "https://studio.youtube.com"
    
    var body: some View {
        VStack(spacing: 0) {
            // Dashboard Top Bar
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "play.tv.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 14, weight: .bold))
                    
                    Text("YouTube Studio 官方直播控制台")
                        .font(.system(size: 13, weight: .bold))
                }
                
                Spacer()
                
                // Channel Info Pill / OAuth Status
                if ytService.isLoggedIn {
                    HStack(spacing: 8) {
                        if !ytService.channelAvatarUrl.isEmpty, let url = URL(string: ytService.channelAvatarUrl) {
                            AsyncImage(url: url) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Image(systemName: "person.crop.circle.fill")
                            }
                            .frame(width: 20, height: 20)
                            .clipShape(Circle())
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .foregroundColor(.red)
                        }
                        
                        Text(ytService.channelTitle)
                            .font(.system(size: 12, weight: .semibold))
                        
                        Text("(\(ytService.subscriberCount) 訂閱者)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        
                        StatusBadge(status: ytService.currentBroadcastStatus)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(12)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("尚未登入 YouTube 頻道")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                
                // Account Manager Button
                Button(action: {
                    if ytService.isLoggedIn {
                        ytService.logout()
                        showToast("已登入帳號")
                    } else {
                        ytService.startOAuthLogin { success, msg in
                            showToast(msg)
                        }
                    }
                }) {
                    Label(ytService.isLoggedIn ? "登出帳號" : "🔑 登入 YouTube 帳號", systemImage: ytService.isLoggedIn ? "rectangle.portrait.and.arrow.right" : "key.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(ytService.isLoggedIn ? Color.gray : Color.red)
                .controlSize(.small)
                
                // Toggle Embed Browser Mode Button
                Button(action: {
                    showWebMonitor.toggle()
                }) {
                    Label(showWebMonitor ? "隱藏 Web 視窗" : "開啟 Web 視窗", systemImage: showWebMonitor ? "rectangle.badge.xmark" : "globe")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            if showWebMonitor {
                // Inline Embedded Web Viewer (For users who also want full web view)
                WebBrowserComponent(initialUrl: webMonitorUrl)
            } else {
                // Native API Live Studio Dashboard Grid
                HStack(alignment: .top, spacing: 16) {
                    // Left Control Column: Broadcast Setup & Stream Key
                    VStack(alignment: .leading, spacing: 10) {
                        Text("🎬 直播活動設定與推流金鑰 (Live Broadcast Controls)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("直播標題:")
                                .font(.system(size: 11, weight: .semibold))
                            TextField("請輸入直播標題", text: $broadcastTitleInput)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                        }
                        
                        // Control Action Buttons
                        HStack(spacing: 8) {
                            Button(action: {
                                ytService.createLiveBroadcast(title: broadcastTitleInput, description: broadcastDescInput) { success, msg in
                                    showToast(msg)
                                }
                            }) {
                                Label("➕ 建立直播活動", systemImage: "plus.circle.fill")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            
                            Button(action: {
                                ytService.transitionBroadcast(status: "LIVE")
                                showToast("🚀 已切換至正式開播 (LIVE) 狀態！")
                            }) {
                                Label("🚀 正式開播 (Go Live)", systemImage: "play.circle.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .controlSize(.small)
                            .disabled(!ytService.isLoggedIn)
                            
                            Button(action: {
                                ytService.transitionBroadcast(status: "OFFLINE")
                                showToast("🛑 已結束直播活動。")
                            }) {
                                Label("🛑 結束直播", systemImage: "stop.circle.fill")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .controlSize(.small)
                            .disabled(ytService.currentBroadcastStatus == "OFFLINE")
                        }
                        
                        Divider()
                        
                        // Stream Key & Ingest URL
                        VStack(alignment: .leading, spacing: 6) {
                            Text("RTMP 推流伺服器與串流金鑰 (Stream Key):")
                                .font(.system(size: 11, weight: .semibold))
                            
                            HStack(spacing: 8) {
                                Text("RTMP 網址:")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Text(ytService.rtmpUrl)
                                    .font(.system(size: 11, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(4)
                                
                                Button("複製") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(ytService.rtmpUrl, forType: .string)
                                    showToast("已複製 RTMP 網址")
                                }
                                .controlSize(.small)
                            }
                            
                            HStack(spacing: 8) {
                                Text("串流金鑰:")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                SecureField("", text: $ytService.streamKey)
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)
                                    .frame(maxWidth: 220)
                                
                                Button("複製金鑰") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(ytService.streamKey, forType: .string)
                                    showToast("已複製串流金鑰！")
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.06))
                    .cornerRadius(8)
                    
                    // Right Real-time Stats Column
                    VStack(alignment: .leading, spacing: 10) {
                        Text("📊 即時直播數據統計 (Real-time Live Analytics)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 12) {
                            MetricCard(icon: "eye.fill", title: "即時觀看人數", value: ytService.activeViewerCount, color: .blue)
                            MetricCard(icon: "hand.thumbsup.fill", title: "點讚數", value: ytService.likeCount, color: .orange)
                            MetricCard(icon: "text.bubble.fill", title: "聊天室動態", value: "正常", color: .green)
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("💡 操作說明:")
                                .font(.system(size: 11, weight: .bold))
                            Text("1. 在【參數設定】中輸入 Google API Client ID & Secret。")
                            Text("2. 點擊右上角【登入 YouTube 帳號】進行 OAuth 2.0 免再登入授權。")
                            Text("3. 點擊【➕ 建立直播活動】取得金鑰並透過此控制台控制切換開播。")
                        }
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color.blue.opacity(0.08))
                        .cornerRadius(6)
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.06))
                    .cornerRadius(8)
                }
                .padding(12)
            }
        }
        .overlay(
            VStack {
                if isShowingStatusMessage {
                    Text(statusMessage)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.85))
                        .cornerRadius(20)
                        .shadow(radius: 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 10)
                }
                Spacer()
            }
        )
    }
    
    private func showToast(_ msg: String) {
        withAnimation {
            statusMessage = msg
            isShowingStatusMessage = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation {
                isShowingStatusMessage = false
            }
        }
    }
}

struct StatusBadge: View {
    let status: String
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusText)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(statusColor.opacity(0.15))
        .cornerRadius(4)
    }
    
    private var statusColor: Color {
        switch status {
        case "LIVE": return .red
        case "TESTING": return .orange
        default: return .gray
        }
    }
    
    private var statusText: String {
        switch status {
        case "LIVE": return "🔴 ON AIR"
        case "TESTING": return "🟡 TESTING"
        default: return "⚪ OFFLINE"
        }
    }
}

struct MetricCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }
}
