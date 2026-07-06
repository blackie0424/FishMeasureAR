# FishMeasureAR — 漁獲 AR 測量 App(MVP 骨架)

釣魚漁獲上岸後的自動測長工具:AR 自動測量魚長、放置真實比例參照物(藍白拖、打火機、鋁罐…)、自動記錄釣點 GPS 與日期。

## 建置步驟(Mac)

```bash
# 1. 安裝 XcodeGen(只需一次)
brew install xcodegen

# 2. 生成 Xcode 專案
cd FishMeasureAR
xcodegen generate

# 3. 開啟並設定簽章
open FishMeasureAR.xcodeproj
# → Signing & Capabilities 選擇你的 Team

# 4. 接實機執行(ARKit 無法用模擬器)
```

**需求:** Xcode 15+、iOS 17+ 實機。完整精度需 LiDAR 機型(iPhone 12 Pro 以上 Pro 系列);非 Pro 機型自動降級為平面推估並於 UI 標示「估計值」。

## 專案結構

```
Sources/
├── App/                      # 入口 + TabView
├── Features/
│   ├── Measure/              # ★ 核心:AR 測量
│   │   ├── MeasureSessionController.swift  # ARSession 管理、雙路徑(LiDAR/raycast)
│   │   ├── FishSegmentation.swift          # Vision 前景分割 + PCA 主軸端點
│   │   ├── DepthUnprojector.swift          # 深度反投影(5x5 中位數抗反光噪點)
│   │   ├── MeasurementSmoother.swift       # 15 幀滑動中位數 + 穩定判定
│   │   └── MeasureScreen.swift             # UI(狀態燈/測量線/快門)
│   ├── ReferenceObjects/     # 參照物庫(真實尺寸)+ 放置邏輯
│   ├── Capture/              # 快照、浮水印、EXIF GPS、相簿存檔
│   ├── Journal/              # 日誌列表/詳情/釣點地圖
│   └── Settings/             # 隱私模式等設定
└── Core/
    ├── Location/             # 定位 + 反向地理編碼
    └── Persistence/          # SwiftData CatchRecord
```

## 已知的骨架限制(第一次實機測試前先看)

1. **座標轉換需實機校驗** — `MeasureSessionController` 裡 Vision 分割座標 ↔ capturedImage ↔ 螢幕座標的旋轉換算(`rotateBackToCapturedImage`、`viewPoint(fromCaptured:)`)是最容易出錯的環節。實測時若測量線與魚體錯位,先檢查這兩個函式。建議先用 A4 紙(29.7cm)驗證。
2. **參照物是程序化幾何佔位** — box/cylinder 尺寸正確但外觀陽春。之後把無商標 USDZ 模型放進 `Resources/USDZ/`,在 `ReferenceObjects.swift` 填入 `usdzName` 並改用 `Entity.load(named:)`。
3. **手動微調端點未實作**(規格 FR-1.4)— 分割把尾鰭膜切掉時暫時無法補救,列為下一迭代。
4. **非同步幀處理的執行緒模型偏保守** — 每 5 幀處理一次 + isProcessing 鎖,實測若延遲明顯可改用 `AsyncStream` 佇列丟棄舊幀。

## 實地驗證計畫(Phase 1 目標)

拿捲尺對照,實測 20 尾以上(不同大小/魚種/光線),記錄:
App 讀值、捲尺實測、機型、拍攝距離與角度。誤差目標:LiDAR 機型 ±1cm 內。

## 授權與法務

參照物模型一律使用無商標 generic 造型,不得加入真實品牌 logo。
