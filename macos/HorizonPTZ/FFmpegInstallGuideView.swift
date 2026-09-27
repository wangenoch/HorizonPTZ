import SwiftUI
import AppKit

struct FFmpegInstallGuideView: View {
    @Binding var isPresented: Bool
    @ObservedObject private var streamManager = PipeStreamManager.shared
    
    @State private var copiedCommand = false
    @State private var checkStatusMessage: String? = nil
    @State private var isChecking = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "sparkles.tv")
                    .font(.system(size: 24))
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("AI 辨識引擎依賴 (FFmpeg) 安裝與下載指引")
                        .font(.headline)
                    Text("HorizonPTZ 即時人數計算需要使用 FFmpeg 進行 RTSP 串流解碼")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Content ScrollView
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Status Banner
                    statusBannerView
                    
                    // Option 1: Terminal / Homebrew (Recommended)
                    option1HomebrewView
                    
                    // Option 2: Direct Download & Drag into App (No Terminal needed)
                    option2DirectDownloadView
                    
                    // Option 3: Manual placement (/usr/local/bin)
                    option3ManualPathView
                }
                .padding(22)
            }
            
            Divider()
            
            // Footer Controls
            HStack {
                Button {
                    checkAvailability()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(isChecking ? 360 : 0))
                            .animation(isChecking ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isChecking)
                        Text("重新檢測安裝狀態")
                    }
                }
                .controlSize(.regular)
                
                if let msg = checkStatusMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(streamManager.isAvailable ? .green : .orange)
                        .transition(.opacity)
                }
                
                Spacer()
                
                Button("完成關閉") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 660, height: 600)
        .onAppear {
            checkAvailability()
        }
    }
    
    // MARK: - Status Banner
    private var statusBannerView: some View {
        HStack(spacing: 12) {
            Image(systemName: streamManager.isAvailable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundColor(streamManager.isAvailable ? .green : .orange)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(streamManager.isAvailable ? "✅ 已成功偵測到 FFmpeg！" : "⚠️ 尚未偵測到 FFmpeg 執行檔")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(streamManager.isAvailable ? .green : .primary)
                
                if let path = streamManager.ffmpegPath {
                    Text("執行檔路徑: \(path)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                } else {
                    Text("請參考下方任一種方案完成安裝，完成後點擊「重新檢測」即可立即啟用 AI 計算。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(14)
        .background(streamManager.isAvailable ? Color.green.opacity(0.1) : Color.orange.opacity(0.12))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(streamManager.isAvailable ? Color.green.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Option 1: Homebrew Terminal
    private var option1HomebrewView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("方案一：終端機一鍵安裝 (最推薦)", systemImage: "terminal.fill")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Text("適合有 Homebrew 的 Mac")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text("如果您已安裝 Homebrew，只需在終端機中執行以下指令即可全自動安裝：")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            
            HStack {
                Text("brew install ffmpeg")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                
                Button {
                    copyToClipboard("brew install ffmpeg")
                    copiedCommand = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copiedCommand = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copiedCommand ? "checkmark" : "doc.on.doc")
                        Text(copiedCommand ? "已複製！" : "複製指令")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                
                Button {
                    openTerminal()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "terminal")
                        Text("開啟終端機")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button {
                    openUrl("https://brew.sh")
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                        Text("Homebrew 官網")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.link)
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
    
    // MARK: - Option 2: Direct Download & Drag into App
    private var option2DirectDownloadView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("方案二：免安裝直接下載 (免終端機)", systemImage: "arrow.down.app.fill")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Text("最簡單、免指令")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            
            Text("直接從 macOS 官方靜態編譯頁面下載 FFmpeg，解壓縮後直接拖入本 App 的資源資料夾即可！")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            
            HStack(spacing: 10) {
                Button {
                    openUrl("https://evermeet.cx/ffmpeg/")
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "safari")
                        Text("前往 Evermeet 官方下載頁面")
                    }
                    .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                
                Button {
                    openUrl("https://ffmpeg.org/download.html")
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                        Text("FFmpeg.org 官方下載頁")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("下載並解壓縮出 `ffmpeg` 執行檔後：")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                
                HStack {
                    Button {
                        openAppResourcesFolder()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.badge.plus")
                                .foregroundColor(.accentColor)
                            Text("📁 點此開啟本 App 的 Resources 資料夾 (將 ffmpeg 拖進去)")
                                .font(.system(size: 11, weight: .bold))
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                }
                
                Text("💡 只要將解壓縮出的 `ffmpeg` 檔案放入此資料夾，回到本視窗點擊「重新檢測」即可立即啟用！")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
    
    // MARK: - Option 3: Manual System Path
    private var option3ManualPathView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("方案三：手動放入系統目錄", systemImage: "internaldrive.fill")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Text("全域通用")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text("您也可以將 `ffmpeg` 執行檔放入 macOS 系統標準命令目錄：")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            
            HStack {
                Text("/usr/local/bin/ffmpeg")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button {
                    openFolder("/usr/local/bin")
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                        Text("打開 /usr/local/bin")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
    
    // MARK: - Helpers
    private func checkAvailability() {
        isChecking = true
        let available = streamManager.checkAvailability()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.isChecking = false
            if available {
                self.checkStatusMessage = "檢測成功：已偵測到 FFmpeg！"
            } else {
                self.checkStatusMessage = "尚未找到 FFmpeg，請確認檔案已放置完成。"
            }
        }
    }
    
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    
    private func openUrl(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func openTerminal() {
        if let terminalUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            NSWorkspace.shared.openApplication(at: terminalUrl, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
    }
    
    private func openAppResourcesFolder() {
        if let resUrl = Bundle.main.resourceURL {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: resUrl.path)
        }
    }
    
    private func openFolder(_ path: String) {
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
        } else {
            // Try to create it or open /usr/local
            try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
        }
    }
}
