import SwiftUI

struct YouTubeStudioDashboardView: View {
    @ObservedObject private var ytService = YouTubeLiveService.shared
    @ObservedObject private var monitorCtrl = LiveMonitorWindowController.shared
    
    @State private var broadcastTitleInput: String = "主日禮拜 / 活動現場直播"
    @State private var broadcastDescInput: String = "HorizonPTZ AI 智慧雙鏡頭自動追蹤串流直播"
    @State private var statusMessage: String = ""
    @State private var isShowingStatusMessage: Bool = false
    
    @State private var showWebMonitor: Bool = false
    @State private var webMonitorUrl: String = "https://studio.youtube.com"
    @State private var chatInputText: String = ""
    @State private var isSendingChat: Bool = false
    
    // 自由左右調整欄位寬度狀態 (持久化記憶使用者調整的偏好)
    @AppStorage("yt_left_col_width") private var leftColWidth: Double = 320
    @AppStorage("yt_right_col_width") private var rightColWidth: Double = 320
    
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
                        
                        // 重新整理按鈕
                        Button(action: {
                            ytService.fetchCurrentLiveBroadcast { success in
                                showToast(success ? "已刷新最新直播與金鑰" : "查無直播活動")
                            }
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderless)
                        .help("重新抓取頻道最新直播與串流碼")
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
                        showToast("已登出 Google 帳號")
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
            
            // 多直播場次切換標籤列 (僅在當天或近期有 2 場以上有效直播時才顯示)
            if ytService.isLoggedIn && ytService.availableBroadcasts.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Image(systemName: "film.stack")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        
                        Text("直播場次:")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        ForEach(ytService.availableBroadcasts) { broadcast in
                            let isSelected = (broadcast.id == ytService.currentBroadcastId)
                            let isWindowOpen = monitorCtrl.isWindowOpen(broadcastId: broadcast.id)
                            
                            HStack(spacing: 6) {
                                Button(action: {
                                    ytService.selectBroadcast(broadcast)
                                }) {
                                    HStack(spacing: 5) {
                                        Circle()
                                            .fill(broadcast.status == "LIVE" ? Color.red : (broadcast.status == "TESTING" ? Color.yellow : Color.gray))
                                            .frame(width: 7, height: 7)
                                        
                                        Text(broadcast.title)
                                            .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                            .lineLimit(1)
                                        
                                        if broadcast.status == "LIVE" {
                                            Text("LIVE")
                                                .font(.system(size: 9, weight: .black))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.red)
                                                .cornerRadius(3)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                
                                // 支援方案 3: 每一場次獨立彈出視窗按鈕
                                Button(action: {
                                    monitorCtrl.toggleWindow(broadcastId: broadcast.id, title: broadcast.title)
                                }) {
                                    Image(systemName: isWindowOpen ? "pip.exit" : "pip.enter")
                                        .font(.system(size: 10))
                                        .foregroundColor(isWindowOpen ? .orange : (isSelected ? .white.opacity(0.8) : .secondary))
                                }
                                .buttonStyle(.plain)
                                .help(isWindowOpen ? "關閉此場次的獨立監看視窗" : "將此場次畫面彈出為獨立置頂視窗（支援同時監看多直播）")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(isSelected ? Color.blue : Color.secondary.opacity(0.12))
                            .foregroundColor(isSelected ? .white : .primary)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isSelected ? Color.blue : Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                
                Divider()
            }
            
            if showWebMonitor {
                // Inline Embedded Web Viewer (保留原本開啟 Web 視窗功能)
                WebBrowserComponent(initialUrl: webMonitorUrl)
            } else {
                // 三欄式專業直播控制台 (流暢支援左右任意向中間/向兩側拖曳調整寬度)
                HStack(spacing: 0) {
                    // 1. Left Column: 🎬 直播活動設定與推流金鑰
                    leftColumnContent
                        .frame(width: CGFloat(leftColWidth))
                        .frame(maxHeight: .infinity)
                    
                    // 左側自訂拖曳調節分割條 (向中間/向左隨意拖動)
                    dragSplitDivider(isLeft: true)
                    
                    // 2. Center Column: 📺 即時直播畫面監看 (Live Stream Video Monitor)
                    centerColumnContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // 右側自訂拖曳調節分割條 (向中間/向右隨意拖動)
                    dragSplitDivider(isLeft: false)
                    
                    // 3. Right Column: 即時統計數據 + 即時聊天室與回覆面板
                    rightColumnContent
                        .frame(width: CGFloat(rightColWidth))
                        .frame(maxHeight: .infinity)
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    // MARK: - 可拖曳分割線 (支援向中間或向兩側自由調整)
    @ViewBuilder
    private func dragSplitDivider(isLeft: Bool) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 8)
            
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.secondary.opacity(0.45))
                .frame(width: 3, height: 26)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if isLeft {
                        let proposed = leftColWidth + Double(value.translation.width)
                        leftColWidth = max(200, min(550, proposed))
                    } else {
                        let proposed = rightColWidth - Double(value.translation.width)
                        rightColWidth = max(200, min(550, proposed))
                    }
                }
        )
    }

    // 1. Left Column Content
    private var leftColumnContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 直播設定與推流控制卡片
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(.blue)
                    Text("🎬 直播活動設定與推流金鑰")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 8) {
                    Text("直播標題:")
                        .font(.system(size: 11, weight: .semibold))
                    TextField("請輸入直播標題", text: $ytService.currentBroadcastTitle)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                }
                
                // Control Action Buttons (等寬排列)
                HStack(spacing: 6) {
                    Button(action: {
                        ytService.createLiveBroadcast(title: ytService.currentBroadcastTitle, description: broadcastDescInput) { success, msg in
                            showToast(msg)
                        }
                    }) {
                        Label("建立活動", systemImage: "plus.circle.fill")
                            .font(.system(size: 10.5, weight: .bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .disabled(!ytService.isLoggedIn)
                    
                    Button(action: {
                        ytService.transitionBroadcast(status: "LIVE") { success, msg in
                            showToast(msg)
                        }
                    }) {
                        Label("正式開播", systemImage: "play.circle.fill")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .disabled(!ytService.isLoggedIn || ytService.currentBroadcastId.isEmpty)
                    
                    Button(action: {
                        ytService.transitionBroadcast(status: "COMPLETE") { success, msg in
                            showToast(msg)
                        }
                    }) {
                        Label("結束直播", systemImage: "stop.circle.fill")
                            .font(.system(size: 10.5, weight: .bold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .disabled(ytService.currentBroadcastStatus == "OFFLINE")
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(8)
            
            // 串流設定 (RTMP / Stream Key)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("RTMP 推流網址:")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Button("複製") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(ytService.rtmpUrl, forType: .string)
                        showToast("已複製 RTMP 網址")
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10))
                }
                
                Text(ytService.rtmpUrl)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(6)
                
                HStack {
                    Text("串流金鑰 (Stream Key):")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Button("複製") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(ytService.streamKey, forType: .string)
                        showToast("已複製串流金鑰")
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10))
                    
                    Button(action: {
                        ytService.fetchCurrentLiveBroadcast { _ in
                            showToast("已重整串流碼")
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .help("重新獲取")
                }
                
                HStack {
                    Text(String(repeating: "•", count: 18))
                        .font(.system(size: 13, design: .monospaced))
                        .lineLimit(1)
                    Spacer()
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(6)
            }
            .padding(10)
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(8)
            
            // 直播狀態指示
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundColor(.blue)
                        .font(.system(size: 11))
                    Text("直播串流狀態")
                        .font(.system(size: 11, weight: .bold))
                    Spacer()
                    StatusBadge(status: ytService.currentBroadcastStatus)
                }
                
                if !ytService.currentBroadcastId.isEmpty {
                    Text("活動 ID: \(ytService.currentBroadcastId)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                Text("💡 提示：點擊「建立活動」後將 RTMP 與金鑰設定至 OBS 或導播機。當推流軟體開始發送訊號後，點擊「正式開播」即時推送到 YouTube。")
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
            .padding(10)
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(8)
            
            Spacer(minLength: 0)
        }
    }

    // 2. Center Column Content
    private var centerColumnContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "tv.fill")
                    .foregroundColor(.red)
                Text("📺 目前直播即時畫面監看 (Live Monitor)")
                    .font(.system(size: 11, weight: .bold))
                
                Spacer()
                
                // 獨立置頂視窗按鈕 (可拉伸、全屏、點擊切換)
                Button(action: {
                    monitorCtrl.toggleWindow(broadcastId: ytService.currentBroadcastId)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: monitorCtrl.isFloating ? "arrow.down.right.and.arrow.up.left" : "pip.enter")
                            .font(.system(size: 10, weight: .semibold))
                        Text(monitorCtrl.isFloating ? "收回主視窗" : "獨立置頂視窗")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .buttonStyle(.bordered)
                .tint(monitorCtrl.isFloating ? .orange : .blue)
                .controlSize(.mini)
                .help(monitorCtrl.isFloating ? "將監看畫面收回主視窗" : "彈出為獨立置頂視窗（可隨意拉伸、全螢幕）")
                
                if !ytService.currentBroadcastId.isEmpty {
                    Link(destination: URL(string: "https://www.youtube.com/watch?v=\(ytService.currentBroadcastId)")!) {
                        HStack(spacing: 4) {
                            Text("在 YouTube 開啟")
                            Image(systemName: "arrow.up.right.square")
                        }
                        .font(.system(size: 10))
                    }
                }
            }
            
            ZStack {
                Color.black
                
                if monitorCtrl.isFloating {
                    VStack(spacing: 8) {
                        Image(systemName: "pip.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.blue)
                        Text("畫面已在獨立置頂視窗中播放")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                        Button("點此收回主視窗") {
                            monitorCtrl.closeWindow()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding()
                } else if !ytService.currentBroadcastId.isEmpty {
                    WebBrowserComponent(
                        initialUrl: "http://localhost:8080/embed?v=\(ytService.currentBroadcastId)",
                        showToolbar: false
                    )
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "video.slash.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.secondary)
                        Text("目前頻道尚無活躍的直播串流活動")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("點擊左側【建立活動】開始推流監看")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                    .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }

    // 3. Right Column Content
    private var rightColumnContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 數據指標卡片
            HStack(spacing: 6) {
                MetricCard(icon: "eye.fill", title: "即時人數", value: ytService.activeViewerCount, color: .blue)
                MetricCard(icon: "hand.thumbsup.fill", title: "點讚數", value: ytService.likeCount, color: .orange)
                MetricCard(icon: "message.fill", title: "聊天訊息", value: "\(ytService.chatMessages.count)", color: .green)
            }
            
            // 即時聊天室卡片
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .foregroundColor(.green)
                    Text("💬 YouTube 直播即時聊天室")
                        .font(.system(size: 11, weight: .bold))
                    
                    Spacer()
                    
                    Button(action: {
                        ytService.pollChatMessages()
                        showToast("已刷新聊天室")
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .help("重新整理聊天室訊息")
                }
                
                // 訊息列表
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            if ytService.chatMessages.isEmpty {
                                VStack(spacing: 6) {
                                    Spacer()
                                    Image(systemName: "ellipsis.bubble")
                                        .font(.system(size: 24))
                                        .foregroundColor(.secondary)
                                    Text("直播尚未開始或未開放聊天室")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, minHeight: 120)
                            } else {
                                ForEach(ytService.chatMessages) { msg in
                                    HStack(alignment: .top, spacing: 6) {
                                        if !msg.authorAvatarUrl.isEmpty, let url = URL(string: msg.authorAvatarUrl) {
                                            AsyncImage(url: url) { image in
                                                image.resizable().aspectRatio(contentMode: .fill)
                                            } placeholder: {
                                                Image(systemName: "person.circle.fill")
                                            }
                                            .frame(width: 18, height: 18)
                                            .clipShape(Circle())
                                        } else {
                                            Image(systemName: "person.circle.fill")
                                                .font(.system(size: 18))
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 1) {
                                            HStack(spacing: 4) {
                                                Text(msg.authorName)
                                                    .font(.system(size: 10.5, weight: .bold))
                                                    .foregroundColor(msg.isChatOwner ? .yellow : .primary)
                                                if msg.isChatOwner {
                                                    Text("頻道主")
                                                        .font(.system(size: 8, weight: .bold))
                                                        .padding(.horizontal, 4)
                                                        .padding(.vertical, 1)
                                                        .background(Color.yellow.opacity(0.2))
                                                        .foregroundColor(.yellow)
                                                        .cornerRadius(3)
                                                }
                                            }
                                            Text(msg.messageText)
                                                .font(.system(size: 11))
                                                .foregroundColor(.primary)
                                        }
                                    }
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .id(msg.id)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(minHeight: 140, maxHeight: .infinity)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(6)
                    .onChange(of: ytService.chatMessages.count) { _ in
                        if let lastId = ytService.chatMessages.last?.id {
                            withAnimation {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                }
                
                // 回覆輸入列
                HStack(spacing: 6) {
                    TextField("以此頻道身份發送聊天室訊息...", text: $chatInputText)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .onSubmit {
                            sendChatAction()
                        }
                    
                    Button(action: {
                        sendChatAction()
                    }) {
                        if isSendingChat {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .controlSize(.small)
                    .disabled(chatInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ytService.activeLiveChatId.isEmpty || isSendingChat)
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(8)
            .frame(maxHeight: .infinity)
        }
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
    
    private func sendChatAction() {
        let text = chatInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        isSendingChat = true
        ytService.sendChatMessage(text: text) { success, msg in
            isSendingChat = false
            if success {
                chatInputText = ""
                showToast("訊息已發送至 YouTube 直播！")
            } else {
                showToast(msg)
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
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(.primary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(6)
    }
}
