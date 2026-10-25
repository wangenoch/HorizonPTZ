# HorizonPTZ 控制中心

<p align="center">
  <b>專業 macOS PTZ 攝影機控制、導播機連線整合、本機 AI 人流辨識與 YouTube Live 直播監控一體化工作台</b><br>
  <i>A professional, local-first macOS desktop controller for PTZ cameras, video switchers, on-device AI headcount, and YouTube Live broadcasting.</i>
</p>

<p align="center">
  <a href="#-繁體中文介紹">繁體中文</a> •
  <a href="#-english-overview">English</a> •
  <a href="#-隱私權政策--privacy-policy">隱私權政策 / Privacy Policy</a> •
  <a href="https://wangenoch.github.io/HorizonPTZ/">官方首頁 (GitHub Pages)</a>
</p>

---

## 🇹🇼 繁體中文介紹

### 💡 專案簡介
**HorizonPTZ** 是一套專為影音轉播室、教會崇拜轉播、活動導播與多機直播工程師量身打造的 macOS 原生控制中樞。結合低延遲攝影機監看、直覺式雲台控制、導播機 Tally 雙向反饋，以及基於 Apple 晶片神經網路引擎（Neural Engine）的 100% 離線 AI 人流統計技術。

### 🌟 核心特色
1. **多機 PTZ 直覺操控**：
   - 支援 VISCA over IP 與 ONVIF 雙重標準網路協議。
   - 獨創「向量式（Vector）」與「畫面抓取移動（Grab-to-Pan）」雙滑鼠控制模式，支援多組鏡頭預設點（Presets）。
   - 支援實體遊戲手把／遙控器（Gamepad）即時搖桿操控與機位快速切換。
2. **本機端 CoreML YOLO AI 人流統計 (On-Device AI)**：
   - 透過 VLCKit 記憶體直接採樣影像，交由 Apple Neural Engine 進行即時推論。
   - **完全不需外部 FFmpeg**，單一 RTSP 連線節省 50% 頻寬與 CPU 負擔。
   - 100% 本機端離線運算，畫面與臉部特徵絕不外流，隱私零風險。
3. **導播機 Tally 雙向整合**：
   - 深度連線 RGBlink mini-pro 專業導播機，具備本地 TCP 即時通訊。
   - 支援綠色（PVW 預監）與紅色（PGM 節目台）雙色即時 Tally 提示燈號。
4. **YouTube Studio 直播工作台**：
   - Google 官方 OAuth 2.0 整合，金鑰加密保存於 macOS Keychain。
   - 實時監看串流健康度（位元率、影格率、解析度）與即時聊天室。
   - 支援彈性雙向拖曳調整欄位，提供多場直播智慧分頁與獨立子母畫面（PiP）浮動監看視窗。
5. **Mac App Store 沙盒規範支援**：
   - 完整遵守 macOS App Sandbox 規範，採用純原生 Swift + SwiftUI + AppKit。
   - 原生 Universal Binary（相容 Apple Silicon M 系列晶片與 Intel Mac）。

---

## 🇺🇸 English Overview

### 💡 Introduction
**HorizonPTZ** is an all-in-one, local-first macOS desktop production controller designed for live streaming operators, houses of worship, multicam broadcasters, and video engineers. It unifies low-latency PTZ camera monitoring, hardware switcher integration, on-device AI computer vision headcount, and YouTube Studio broadcasting telemetry into a responsive single dashboard.

### 🌟 Key Capabilities
1. **Precision Multicam PTZ Control**:
   - Comprehensive VISCA over IP and ONVIF network protocol support.
   - Dual mouse navigation: intuitive vector panning and direct grab-to-pan dragging with one-click camera preset recalls.
   - Physical gamepad controller support for smooth joystick panning and quick camera switching.
2. **On-Device CoreML YOLO AI Inference**:
   - Direct in-memory RTSP frame sampling powered by VLCKit and processed via Apple's Neural Engine.
   - **Zero external FFmpeg dependencies**: single RTSP connection per camera saves 50% bandwidth and processing overhead.
   - 100% private, offline headcount analytics without cloud latency or third-party servers.
3. **Hardware Switcher & Tally Sync**:
   - Native TCP client and server listener for RGBlink mini-pro video switchers.
   - Live two-way Tally state feedback with visual Program (Red) and Preview (Green) indicators.
4. **YouTube Live Broadcasting Studio**:
   - Official Google OAuth 2.0 with secure macOS Keychain token storage.
   - Live stream telemetry diagnostics (bitrate, fps, resolution status) and real-time live chat stream.
   - Customizable bidirectional resizable sidebars, multi-broadcast smart switcher, and pop-out PiP monitor windows.
5. **App Store & Sandbox Ready**:
   - Sandboxed per Apple Mac App Store guidelines (`com.apple.security.app-sandbox`).
   - Native Universal Binary supporting Apple Silicon (`arm64`) and Intel (`x86_64`).

---

## 🔒 隱私權政策 / Privacy Policy

本應用程式採用嚴格的「本地優先（Local-First）」架構：
- 不設任何後端追蹤伺服器，不收集、不出售任何使用者資料。
- 攝影機影格與 AI 辨識運算全數在本機記憶體內完成，絕不上傳雲端。
- 網路權限嚴格限制在本地區域網路（LAN）與 Google 官方 API 連線。

📄 **詳細政策文件：**
- [docs/PRIVACY_POLICY.md](docs/PRIVACY_POLICY.md) (中英雙語 Markdown)
- [線上網頁版 (GitHub Pages)](https://wangenoch.github.io/HorizonPTZ/)

---

## 🛠️ 系統需求 (System Requirements)

- **作業系統 (OS)**：macOS 13.0 (Ventura) 或更高版本
- **處理器 (Architecture)**：Apple Silicon (M1/M2/M3/M4) 或 Intel Core 系列處理器
- **網路需求**：支援同一區域網路（LAN）下的 RTSP / VISCA PTZ 攝影機與導播機

---

## 📬 聯絡與支援 (Contact & Support)

- **開發者 (Developer)**：Enoch Wang
- **電子郵件 (Email)**：[enoch.wang300@gmail.com](mailto:enoch.wang300@gmail.com)
- **專案原始碼 (GitHub)**：[https://github.com/wangenoch/HorizonPTZ](https://github.com/wangenoch/HorizonPTZ)
