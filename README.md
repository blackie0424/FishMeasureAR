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

## 工作流

```
拍照(測距儀式兩點量測/單拍/連拍) → [量魚+比例尺(未設點的照片)] → 表單(魚種*/漁法) → 統計(今日調查/CSV)
```

- **測距儀式量測(仿 iOS 測距儀)**:準星對準表面 → 按「＋」設 A 點(吻端)→ 移動到尾叉設 B 點。
  點位以世界座標錨定(移動手機仍貼在物體上),數字氣泡直接貼在量測線上即時更新;
  快門時 3D 線段隨快照入照片、長度標籤合成於線旁,存入相簿。兩點齊備的單拍直達表單。
- **拍攝版面**:上下黑帶放全部控制項,中間 3:4 相機預覽只留準星與數字氣泡;
  主按鈕唯一一顆,依情境自動切換「＋設點 → 快門」(邏輯在 Kit `CaptureControls`,有測試)。
- 未設點就拍(或連拍佇列補量)→ 走量魚(拖端點)+比例尺(已知尺寸物換算)路徑,存檔時把線+標籤畫進照片
- 連拍模式先拍照入佇列,統計頁「去量」批次補量(佇列目前僅存於記憶體)
- 統計頁:種類長條、尺寸分布(0-15/15-25/25-35/35-50/50-70/70+)、CSV 匯出

## 專案結構

```
FishMeasureKit/               # ★ 純邏輯 SwiftPM 套件(Linux 可測,TDD)
├── Sources/FishMeasureKit/
│   ├── MeasureFlow.swift             # 五畫面工作流狀態機
│   ├── PixelScaleMeasurement.swift   # 像素↔公分換算(比例尺/端點微調)
│   ├── CatchStatistics.swift         # 種類長條/尺寸分布
│   ├── CSVExporter.swift             # RFC4180 匯出
│   └── ScaleReference.swift          # 參照物真實尺寸目錄(單一事實來源)
└── Tests/FishMeasureKitTests/        # 單元測試(swift test)

Sources/
├── App/                      # 入口 + TabView
├── Features/
│   ├── Flow/                 # ★ 工作流 UI(拍照/量魚/比例尺/表單/統計)
│   ├── Measure/              # AR 測量引擎(session/分割/深度/平滑)
│   ├── ReferenceObjects/     # AR 參照物幾何 + 放置邏輯
│   ├── Capture/              # 快照、浮水印、EXIF GPS、相簿存檔
│   ├── Journal/              # 日誌列表/詳情/釣點地圖(全部歷史)
│   └── Settings/             # 隱私模式等設定
└── Core/
    ├── Location/             # 定位 + 反向地理編碼
    └── Persistence/          # SwiftData CatchRecord
```

## 測試與 CI

```bash
# 核心邏輯單元測試(macOS/Linux 皆可)
swift test --package-path FishMeasureKit
```

GitHub Actions(`.github/workflows/ci.yml`):`kit-tests`(Linux, swift test)+ `app-build`(macOS, iOS Simulator 編譯)。PR 必須全綠才可 merge。

## 已知的骨架限制(第一次實機測試前先看)

1. **座標轉換需實機校驗** — `MeasureSessionController` 裡 Vision 分割座標 ↔ capturedImage ↔ 螢幕座標的旋轉換算(`rotateBackToCapturedImage`、`viewPoint(fromCaptured:)`)是最容易出錯的環節。實測時若測量線與魚體錯位,先檢查這兩個函式。建議先用 A4 紙(29.7cm)驗證。
2. **參照物是程序化幾何佔位** — box/cylinder 尺寸正確但外觀陽春。之後把無商標 USDZ 模型放進 `Resources/USDZ/`,在 `ReferenceObjects.swift` 填入 `usdzName` 並改用 `Entity.load(named:)`。
3. ~~手動微調端點未實作(規格 FR-1.4)~~ — 已由「量魚」畫面的拖曳端點實作(AR 讀值以 cm/px 等比重算;此近似假設垂直俯拍,實機驗證見下)。
5. **連拍佇列僅存於記憶體** — App 結束即遺失,持久化(存暫存照片檔)列為下一迭代。
4. **非同步幀處理的執行緒模型偏保守** — 每 5 幀處理一次 + isProcessing 鎖,實測若延遲明顯可改用 `AsyncStream` 佇列丟棄舊幀。

## 實地驗證計畫(Phase 1 目標)

拿捲尺對照,實測 20 尾以上(不同大小/魚種/光線),記錄:
App 讀值、捲尺實測、機型、拍攝距離與角度。誤差目標:LiDAR 機型 ±1cm 內。

## 授權與法務

參照物模型一律使用無商標 generic 造型,不得加入真實品牌 logo。
