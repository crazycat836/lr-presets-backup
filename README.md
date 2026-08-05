# Lightroom Classic 風格檔一鍵備份／還原

重裝 Lightroom Classic 前後，一鍵備份與還原你的**風格檔**（第三方 film packs、個人 presets/profiles、最愛與隱藏群組）。LR app 本身的設定不在範圍內（可重裝後重設）。

## 使用

雙擊 **`LR 風格檔備份.app`**（原生 SwiftUI app）：
- 一個視窗：上方「立即備份」，中間列出所有備份（最新在最上）可選取還原，下方顯示操作紀錄。
- 還原前會再確認一次，覆蓋同名檔但不刪你其他既有 preset。
- 另有「開啟備份資料夾」按鈕。

> 原始碼在 `swift-app/Sources/`，備份／還原邏輯用 Swift（`FileManager` + `tar`）實作。
> 重新編譯（只需 Command Line Tools，不需完整 Xcode）：`swift-app/build.sh`
>
> 註：本機只有 CLT 沒有 Xcode，故用 `swiftc` 直接編譯 + 手動打包 `.app`；`@State` 因缺 SwiftUIMacros plugin 不可用，故狀態集中在 `AppModel`（`@StateObject`/`@Published`）。

## 備份到哪

每次備份產生一個 timestamped 壓縮檔：

```
~/Documents/LR-Presets-Backup/lr-presets-YYYY-MM-DD-HHMMSS.tar.gz
```

（放在 Documents，重裝 / 解除安裝 LR 不會動到。）

## 備份範圍

來源根目錄：`~/Library/Application Support/Adobe/`

| 項目 | 內容 |
|------|------|
| `Lightroom/` | 你自建的 Develop / Export / Metadata presets |
| `CameraRaw/Settings/` | 所有 film packs（VSCO / RNI / Mitch Lally / SamAlive 等）＋個人 presets/profiles |
| `CameraRaw/Defaults/` | 相機預設 **＋最愛／隱藏群組**（`FavoriteStyles.xmp`） |
| `CameraRaw/ImportedSettings/` | 匯入的設定 |
| `CameraRaw/CameraProfiles/` | 自訂／第三方相機描述檔（DCP） |
| `CameraRaw/LensProfiles/` | 自訂鏡頭描述檔 |
| `CameraRaw/Curves/`、`LocalCorrections/`、`LensProfileDefaults/` | 自訂曲線、局部調整預設、鏡頭校正預設 |

**不備份**：`CameraRaw/ModelZoo`（AI 模型，重裝自動重建）、Logs、GPU cache、LR app 偏好 plist。

> 最愛（Favorites）存在 `CameraRaw/Defaults/FavoriteStyles.xmp`，以 preset 內部 UUID 記錄。因為備份／還原的是同一批 preset 檔，UUID 不變，還原後最愛會正確對回。

## 重裝流程建議

1. 開啟 `LR 風格檔備份.app` 按「立即備份」，確認 `~/Documents/LR-Presets-Backup/` 產生了 `.tar.gz` 且大小合理。
2. 重裝 / 解除安裝並重新安裝 Lightroom Classic。
3. （建議）先啟動 LR 一次再完全關閉，讓它建好資料夾。
4. 回到 app 選取該備份按「還原選取的備份」，確認後即還原。
5. 重開 Lightroom Classic，檢查 presets / profiles / 最愛都在。

## 安全性

- 備份為唯讀複製，不修改／刪除任何 LR 來源資料。
- 還原用 `tar` 解壓：覆蓋同名檔，但**不刪除**你其他既有的 preset。
- 還原前請先完全關閉 Lightroom Classic，避免檔案被鎖。
