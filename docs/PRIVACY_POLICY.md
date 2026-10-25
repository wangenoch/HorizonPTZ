# Privacy Policy for HorizonPTZ

**Last Updated: October 25, 2026**

HorizonPTZ ("we", "our", or "the Application") is a macOS desktop controller application designed for PTZ camera management, video switcher integration, AI person-counting assistance, and YouTube Live broadcasting monitoring.

We respect your privacy and are committed to protecting personal data. This Privacy Policy explains what information the Application accesses, how it is handled, and your choices.

---

## 1. Information Collection and Handling

HorizonPTZ operates as a local utility application. **We do not operate backend tracking servers, and we do not collect, store, sell, or transmit your personal data to any external parties.**

### A. Camera Video Streams & AI Processing
- **Local RTSP Video Streaming**: The Application connects directly to your local PTZ cameras via RTSP (Real-Time Streaming Protocol).
- **On-Device AI Inference**: All computer vision and person-counting features (via Apple Vision and CoreML YOLO) are processed **entirely locally in your Mac's on-chip Neural Engine / GPU / RAM**. No video frames, camera snapshots, or facial data are ever uploaded to the cloud or remote servers.

### B. Device Configuration & Network Communication
- **Local Hardware Control**: Camera IP addresses, VISCA/ONVIF port settings, and video switcher connection details are stored strictly in your local macOS preferences (`UserDefaults`).
- **Local Network Access**: Network requests to your hardware (cameras, RGBlink switchers) remain entirely within your Local Area Network (LAN).

### C. YouTube Account & Live Streaming Integration
- **OAuth 2.0 Authentication**: If you choose to connect your YouTube Studio account, authentication is performed directly with Google's OAuth 2.0 service.
- **Tokens Storage**: Access and refresh tokens are stored securely on your local device (in macOS secure storage / Keychain) solely to fetch stream health metrics, viewer counts, and chat messages via the official Google YouTube Live Streaming API.
- **No Third-Party Sharing**: We do not share, sell, or proxy your YouTube data to any third party. Your usage of YouTube services through HorizonPTZ is also governed by Google's Privacy Policy at [https://policies.google.com/privacy](https://policies.google.com/privacy).

---

## 2. Permissions & Entitlements

In accordance with Apple Mac App Store guidelines, HorizonPTZ runs within the macOS App Sandbox and requests only the minimal necessary entitlements:
- `com.apple.security.network.client`: Required to connect to local PTZ cameras, video switchers, and the YouTube API.
- `com.apple.security.network.server`: Required for local tally feedback / port listener integration with video switchers.
- `com.apple.security.keychain`: Required for encrypting and securely retaining your YouTube API authentication tokens.

---

## 3. Data Retention and Deletion
- Since all data is stored locally on your device, you have complete control over your data.
- You can revoke YouTube access at any time within the Application settings or via your [Google Account Security Settings](https://myaccount.google.com/permissions).
- Uninstalling the Application will remove local preferences and cached data.

---

## 4. Children's Privacy
HorizonPTZ is a professional video production tool and does not knowingly collect any personal identifiable information from children under 13.

---

## 5. Changes to This Privacy Policy
We may update this Privacy Policy from time to time to reflect changes in legal requirements or Application features. Any changes will be posted on this page with an updated "Last Updated" date.

---

## 6. Contact Us
If you have any questions or feedback regarding this Privacy Policy or the security of HorizonPTZ, please contact us:

- **Developer**: Enoch Wang
- **Email**: [enoch.wang300@gmail.com](mailto:enoch.wang300@gmail.com)
- **GitHub Repository**: [https://github.com/wangenoch/HorizonPTZ](https://github.com/wangenoch/HorizonPTZ)

---

*(You can also read the [Traditional Chinese version below](#隱私權政策-horizonptz-繁體中文))*

<br/>

---

# 隱私權政策 (HorizonPTZ 繁體中文)

**最後更新日期：2026 年 10 月 25 日**

HorizonPTZ（以下簡稱「本應用程式」）是一套專為 macOS 設計的專業 PTZ 攝影機控制、導播機連線整合、AI 人流辨識輔助與 YouTube 直播即時監控軟體。

我們極度重視您的隱私，並致力於保護您的個人資料。本隱私權政策旨在說明本應用程式如何存取、處理您的資料以及您的權利。

---

## 一、 資料收集與處理原則

HorizonPTZ 採用「本地優先（Local-First）」架構。**我們未架設任何第三方數據追蹤伺服器，絕不收集、不出售、亦不向任何第三方傳輸您的個人敏感資料。**

### 1. 攝影機影像串流與 AI 辨識
- **本地 RTSP 串流**：本應用程式直接透過區域網路與您的 PTZ 攝影機建立 RTSP 視訊連線。
- **裝置端本地推論 (On-Device AI)**：所有影像辨識與人流統計均透過 Apple 晶片內建之神經網路引擎 (Neural Engine / GPU) 在**您的 Mac 本機記憶體**中完成即時運算。**絕不**將任何監視畫面、影格、截圖或人臉特徵上傳至雲端或遠端伺服器。

### 2. 設備連線與網路通訊
- **硬體控制資訊**：您所設定的攝影機 IP、VISCA 連線埠、導播機 IP 等參數，均僅儲存於您本機的 macOS 偏好設定（`UserDefaults`）中。
- **區域網路通訊**：對攝影機與 RGBlink 導播機的所有控制指令均嚴格限制在您的區域網路（LAN）內傳輸。

### 3. YouTube 帳號與直播功能整合
- **官方 OAuth 2.0 授權**：若您啟用 YouTube 直播控制台，授權流程直接與 Google 官方驗證伺服器對接。
- **金鑰安全儲存**：授權憑證（Token）僅保存在您 Mac 的安全儲存區（Keychain），僅用於透過 Google 官方 YouTube Live Streaming API 讀取您當前的直播健康度、觀看人數與即時留言。
- **無第三方分享**：本應用程式不會將您的 YouTube 資訊轉發至外部。您使用 YouTube 服務時亦受 [Google 隱私權政策](https://policies.google.com/privacy) 規範。

---

## 二、 系統權限與沙盒規範 (App Sandbox)

依據 Apple Mac App Store 審查指南，HorizonPTZ 完整運行於 macOS 沙盒（Sandbox）安全架構內，僅請求必要權限：
- `網路連線 (Client)`：用於連線區域網路攝影機、導播機及 YouTube API。
- `網路接收 (Server)`：用於接收導播機本地 Tally/監聽訊號。
- `鑰匙圈存取 (Keychain)`：用於在本機加密保存您的 YouTube API 授權凭據。

---

## 三、 資料保存與刪除
所有設定資料均保存在您的本機裝置中。您可以隨時在軟體內登出 YouTube，或前往 [Google 帳戶安全性設定](https://myaccount.google.com/permissions) 撤銷授權；移除本應用程式即可完整清除本機相關設定。

---

## 四、 聯絡我們
若您對本隱私權政策有任何疑問或建議，歡迎透過以下方式聯繫開發團隊：

- **開發者**：Enoch Wang
- **電子郵件**：[enoch.wang300@gmail.com](mailto:enoch.wang300@gmail.com)
- **GitHub 專案**：[https://github.com/wangenoch/HorizonPTZ](https://github.com/wangenoch/HorizonPTZ)
