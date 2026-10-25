import SwiftUI
import WebKit

class WebNavigationHelper: ObservableObject {
    var webView: WKWebView?
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var currentUrl: String
    @Published var htmlContent: String? = nil
    @Published var isLoading = false
    
    init(defaultUrl: String = "https://studio.youtube.com/", htmlContent: String? = nil) {
        self.currentUrl = defaultUrl
        self.htmlContent = htmlContent
    }
    
    func load(urlString: String) {
        if let url = URL(string: urlString) {
            var request = URLRequest(url: url)
            request.setValue("https://www.youtube.com", forHTTPHeaderField: "Referer")
            request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
            webView?.load(request)
        }
    }
    
    func loadHTML(htmlString: String, baseURL: URL? = URL(string: "https://www.youtube.com")) {
        webView?.loadHTMLString(htmlString, baseURL: baseURL)
    }
    
    func goBack() {
        webView?.goBack()
    }
    
    func goForward() {
        webView?.goForward()
    }
    
    func reload() {
        if isLoading {
            webView?.stopLoading()
        } else {
            webView?.reload()
        }
    }
}

struct WebView: NSViewRepresentable {
    @ObservedObject var helper: WebNavigationHelper
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        helper.webView = webView
        
        // Configure developer tools, popups, and web settings
        webView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        
        // Set modern desktop Safari User-Agent to bypass YouTube Studio "unsupported browser" warnings
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
        
        if let html = helper.htmlContent {
            webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
        } else if let url = URL(string: helper.currentUrl) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Dynamic updates handled by helper instance
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(helper: helper)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var helper: WebNavigationHelper
        
        init(helper: WebNavigationHelper) {
            self.helper = helper
        }
        
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
        
        private func logToFile(_ message: String) {
            let logPath = "/Users/enoch/.gemini/antigravity/app.log"
            let timestamp = Date().description
            let logLine = "[\(timestamp)] [WEB] \(message)\n"
            if let data = logLine.data(using: .utf8) {
                if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                } else {
                    try? logLine.write(toFile: logPath, atomically: true, encoding: .utf8)
                }
            }
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.helper.isLoading = true
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.helper.isLoading = false
                self.helper.canGoBack = webView.canGoBack
                self.helper.canGoForward = webView.canGoForward
                if let url = webView.url {
                    self.helper.currentUrl = url.absoluteString
                }
            }
            
            // Auto login on camera config pages (local IPs)
            if let urlStr = webView.url?.absoluteString, urlStr.contains("192.168.5.") {
                // Debug element structure
                let debugJs = """
                (function() {
                    var result = "URL: " + window.location.href + "\\n";
                    function inspectDoc(doc, prefix) {
                        if (!doc) return prefix + "null doc\\n";
                        var info = "";
                        var inputs = doc.getElementsByTagName('input');
                        info += prefix + "Inputs (" + inputs.length + "):\\n";
                        for (var i = 0; i < inputs.length; i++) {
                            var inp = inputs[i];
                            info += prefix + "  - tag: " + inp.tagName + ", type: " + inp.type + ", id: " + inp.id + ", name: " + inp.name + ", value: " + inp.value + ", visible: " + (inp.offsetWidth > 0) + "\\n";
                        }
                        var buttons = doc.getElementsByTagName('button');
                        info += prefix + "Buttons (" + buttons.length + "):\\n";
                        for (var i = 0; i < buttons.length; i++) {
                            var btn = buttons[i];
                            info += prefix + "  - tag: " + btn.tagName + ", id: " + btn.id + ", name: " + btn.name + ", text: " + btn.innerText + ", visible: " + (btn.offsetWidth > 0) + "\\n";
                        }
                        var iframes = doc.getElementsByTagName('iframe');
                        info += prefix + "iFrames (" + iframes.length + "):\\n";
                        for (var i = 0; i < iframes.length; i++) {
                            var f = iframes[i];
                            info += prefix + "  Frame " + i + " id: " + f.id + ", name: " + f.name + ", src: " + f.src + "\\n";
                            try {
                                var frameDoc = f.contentDocument || f.contentWindow.document;
                                info += inspectDoc(frameDoc, prefix + "    ");
                            } catch (e) {
                                info += prefix + "    [Access Denied: " + e.message + "]\\n";
                            }
                        }
                        var frames = doc.getElementsByTagName('frame');
                        info += prefix + "Frames (" + frames.length + "):\\n";
                        for (var i = 0; i < frames.length; i++) {
                            var f = frames[i];
                            info += prefix + "  Frame " + i + " id: " + f.id + ", name: " + f.name + ", src: " + f.src + "\\n";
                            try {
                                var frameDoc = f.contentDocument || f.contentWindow.document;
                                info += inspectDoc(frameDoc, prefix + "    ");
                            } catch (e) {
                                info += prefix + "    [Access Denied: " + e.message + "]\\n";
                            }
                        }
                        return info;
                    }
                    return result + inspectDoc(document, "");
                })();
                """
                webView.evaluateJavaScript(debugJs) { res, err in
                    if let output = res as? String {
                        self.logToFile("=== WEB VIEW INSPECTION ===\n\(output)============================")
                    } else if let err = err {
                        self.logToFile("=== WEB VIEW INSPECTION ERROR ===: \(err.localizedDescription)")
                    }
                }
                
                let js = """
                (function() {
                    var maxAttempts = 15; // Try for 7.5 seconds
                    var attempts = 0;
                    
                    var interval = setInterval(function() {
                        attempts++;
                        if (attempts > maxAttempts) {
                            clearInterval(interval);
                            return;
                        }
                        
                        function isVisible(el) {
                            return !!(el.offsetWidth || el.offsetHeight || el.getClientRects().length);
                        }
                        
                        function findInputsInDoc(doc) {
                            if (!doc) return null;
                            
                            // Find username
                            var userEl = null;
                            var userSelectors = [
                                '#edtUserName', '#username', '#txtUserName',
                                'input[id="edtUserName"]', 'input[id="username"]', 'input[id="txtUserName"]',
                                'input[name="username"]', 'input[name="txtUserName"]',
                                'input[id*="username" i]', 'input[name*="username" i]',
                                'input[id*="user" i]', 'input[name*="user" i]'
                            ];
                            for (var i = 0; i < userSelectors.length; i++) {
                                var el = doc.querySelector(userSelectors[i]);
                                if (el && isVisible(el)) {
                                    userEl = el;
                                    break;
                                }
                            }
                            if (!userEl) {
                                var inputs = doc.querySelectorAll('input');
                                for (var i = 0; i < inputs.length; i++) {
                                    var input = inputs[i];
                                    if ((input.type === 'text' || !input.type) && isVisible(input)) {
                                        userEl = input;
                                        break;
                                    }
                                }
                            }
                            
                            // Find password
                            var passEl = null;
                            var passSelectors = [
                                '#edtPassword', '#password', '#txtPassword',
                                'input[type="password"]',
                                'input[id="edtPassword"]', 'input[id="password"]', 'input[id="txtPassword"]',
                                'input[name="password"]', 'input[name="txtPassword"]',
                                'input[id*="pass" i]', 'input[name*="pass" i]',
                                'input[id*="pwd" i]', 'input[name*="pwd" i]'
                            ];
                            for (var i = 0; i < passSelectors.length; i++) {
                                var el = doc.querySelector(passSelectors[i]);
                                if (el && isVisible(el)) {
                                    passEl = el;
                                    break;
                                }
                            }
                            if (!passEl) {
                                var inputs = doc.querySelectorAll('input');
                                for (var i = 0; i < inputs.length; i++) {
                                    var input = inputs[i];
                                    if (input.type === 'password' && isVisible(input)) {
                                        passEl = input;
                                        break;
                                    }
                                }
                            }
                            
                            if (userEl && passEl) {
                                return { user: userEl, pass: passEl, doc: doc };
                            }
                            
                            // Search iframes
                            var iframes = doc.getElementsByTagName('iframe');
                            for (var i = 0; i < iframes.length; i++) {
                                try {
                                    var frameDoc = iframes[i].contentDocument || iframes[i].contentWindow.document;
                                    var res = findInputsInDoc(frameDoc);
                                    if (res) return res;
                                } catch(e) {}
                            }
                            
                            // Search frames
                            var frames = doc.getElementsByTagName('frame');
                            for (var i = 0; i < frames.length; i++) {
                                try {
                                    var frameDoc = frames[i].contentDocument || frames[i].contentWindow.document;
                                    var res = findInputsInDoc(frameDoc);
                                    if (res) return res;
                                } catch(e) {}
                            }
                            
                            return null;
                        }

                        var res = findInputsInDoc(document);
                        if (res) {
                            clearInterval(interval); // Found inputs! Stop polling.
                            
                            var userEl = res.user;
                            var passEl = res.pass;
                            var targetDoc = res.doc;
                            
                            userEl.value = 'admin';
                            passEl.value = 'admin';
                            
                            userEl.dispatchEvent(new Event('input', { bubbles: true }));
                            userEl.dispatchEvent(new Event('change', { bubbles: true }));
                            passEl.dispatchEvent(new Event('input', { bubbles: true }));
                            passEl.dispatchEvent(new Event('change', { bubbles: true }));
                            
                            // Find login button
                            var loginBtn = targetDoc.getElementById('login') || 
                                           targetDoc.getElementById('btnLogin') ||
                                           targetDoc.querySelector('#login') ||
                                           targetDoc.querySelector('#btnLogin');
                                           
                            if (!loginBtn) {
                                var btnSelectors = [
                                    'input[id="login"]', 'input[id="btnLogin"]',
                                    'button[id="login"]', 'button[id="btnLogin"]',
                                    'input[type="submit"]', 'button[type="submit"]',
                                    '.login-btn', '.btn-login', 'input[class*="login" i]', 'button[class*="login" i]'
                                ];
                                for (var i = 0; i < btnSelectors.length; i++) {
                                    var el = targetDoc.querySelector(btnSelectors[i]);
                                    if (el && isVisible(el)) {
                                        loginBtn = el;
                                        break;
                                    }
                                }
                            }
                            
                            if (!loginBtn) {
                                var elements = targetDoc.getElementsByTagName('*');
                                for (var i = 0; i < elements.length; i++) {
                                    var el = elements[i];
                                    if (isVisible(el) && (el.tagName === 'INPUT' || el.tagName === 'BUTTON' || el.tagName === 'DIV' || el.tagName === 'A')) {
                                        var text = el.innerText || '';
                                        var val = el.value || '';
                                        if (text.indexOf('登录') !== -1 || text.indexOf('Login') !== -1 ||
                                            val.indexOf('登录') !== -1 || val.indexOf('Login') !== -1) {
                                            loginBtn = el;
                                            break;
                                        }
                                    }
                                }
                            }
                            
                            if (loginBtn) {
                                setTimeout(function() {
                                    loginBtn.click();
                                }, 200);
                            }
                        }
                    }, 500);
                })();
                """
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
            
            // 如果是 YouTube 監看頁面，自動隱藏頂部導覽列與邊欄，聚焦在影片播放器
            if let urlStr = webView.url?.absoluteString, urlStr.contains("youtube.com") {
                let ytFocusJs = """
                (function() {
                    function applyCleanStyles() {
                        var style = document.getElementById('horizon-clean-yt-style');
                        if (!style) {
                            style = document.createElement('style');
                            style.id = 'horizon-clean-yt-style';
                            document.head.appendChild(style);
                        }
                        style.innerHTML = `
                            #masthead-container, ytd-masthead, #guide, #secondary, #below, #chat-container, #header, #related, ytd-browse, #contents { display: none !important; }
                            #page-manager { margin-top: 0 !important; }
                            ytd-watch-flexy { padding: 0 !important; margin: 0 !important; }
                            #player-container-outer, #player-container-inner, #player-container { 
                                position: fixed !important; 
                                top: 0 !important; 
                                left: 0 !important; 
                                width: 100vw !important; 
                                height: 100vh !important; 
                                max-height: 100vh !important; 
                                z-index: 999999 !important; 
                                background: #000 !important; 
                            }
                            .html5-video-player { width: 100% !important; height: 100% !important; }
                            video { width: 100% !important; height: 100% !important; object-fit: contain !important; }
                        `;
                    }
                    applyCleanStyles();
                    setInterval(applyCleanStyles, 1000);
                })();
                """
                webView.evaluateJavaScript(ytFocusJs, completionHandler: nil)
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.helper.isLoading = false
            }
        }
    }
}

struct WebBrowserComponent: View {
    let initialUrl: String
    let htmlContent: String?
    let showToolbar: Bool
    
    @StateObject private var webHelper: WebNavigationHelper
    @State private var urlInput: String
    @State private var isToolbarVisible: Bool
    
    init(initialUrl: String = "https://studio.youtube.com/", htmlContent: String? = nil, showToolbar: Bool = true) {
        self.initialUrl = initialUrl
        self.htmlContent = htmlContent
        self.showToolbar = showToolbar
        self._webHelper = StateObject(wrappedValue: WebNavigationHelper(defaultUrl: initialUrl, htmlContent: htmlContent))
        self._urlInput = State(initialValue: initialUrl)
        self._isToolbarVisible = State(initialValue: showToolbar)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Browser Navigation Toolbar
            if isToolbarVisible {
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Button(action: { webHelper.goBack() }) {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(!webHelper.canGoBack)
                        .buttonStyle(.borderless)
                        
                        Button(action: { webHelper.goForward() }) {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(!webHelper.canGoForward)
                        .buttonStyle(.borderless)
                        
                        Button(action: { webHelper.reload() }) {
                            Image(systemName: webHelper.isLoading ? "xmark" : "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        
                        Button(action: { webHelper.load(urlString: initialUrl) }) {
                            Image(systemName: "house")
                        }
                        .buttonStyle(.borderless)
                        
                        Button(action: { webHelper.load(urlString: "https://studio.youtube.com/") }) {
                            Image(systemName: "play.rectangle.fill")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                        .help("開啟 YouTube Studio 直播後台")
                    }
                    
                    TextField("網址", text: $urlInput, onCommit: {
                        var target = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !target.isEmpty {
                            if !target.lowercased().hasPrefix("http://") && !target.lowercased().hasPrefix("https://") {
                                target = "https://" + target
                            }
                            webHelper.load(urlString: target)
                        }
                    })
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: webHelper.currentUrl) { newValue in
                        urlInput = newValue
                    }
                    
                    if webHelper.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                    
                    Button(action: {
                        withAnimation {
                            isToolbarVisible = false
                        }
                    }) {
                        Image(systemName: "eye.slash")
                    }
                    .buttonStyle(.borderless)
                    .help("隱藏網址與導覽列")
                }
                .padding(6)
                .background(Color(nsColor: .windowBackgroundColor))
                
                Divider()
            }
            
            // WebView + Floating show button
            ZStack(alignment: .topTrailing) {
                WebView(helper: webHelper)
                
                if !isToolbarVisible {
                    Button(action: {
                        withAnimation {
                            isToolbarVisible = true
                        }
                    }) {
                        Image(systemName: "eye")
                            .font(.system(size: 11))
                            .padding(4)
                            .background(Color(nsColor: .windowBackgroundColor).opacity(0.85))
                            .cornerRadius(4)
                            .shadow(radius: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .help("顯示網址與導覽列")
                    .transition(.opacity)
                }
            }
        }
    }
}
