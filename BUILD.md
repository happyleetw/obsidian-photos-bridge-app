# Obsidian Photos Bridge App - 構建說明

## 開發環境需求

- **macOS**: 12.0 或更新版本
- **Xcode**: 14.0 或更新版本  
- **Swift**: 5.7 或更新版本
- **Swift Package Manager**: 用於依賴管理

## 快速開始

### 1. 克隆專案
```bash
git clone <repository-url>
cd obsidian-photos-bridge-app
```

### 2. 使用 Swift Package Manager 構建
```bash
# 下載依賴
swift package resolve

# 構建專案
swift build

# 執行應用程式
swift run
```

### 3. 使用 Xcode 開發
```bash
# 生成 Xcode 專案檔案
swift package generate-xcodeproj

# 開啟 Xcode
open ObsidianPhotosBridge.xcodeproj
```

## 專案結構

```
Sources/
├── main.swift              # 應用程式入口點
├── PhotosManager.swift     # Photos Framework 管理
├── APIServer.swift         # HTTP API 服務器
├── FileExporter.swift      # 檔案匯出功能
└── Models/
    └── PhotoModel.swift    # 資料模型定義
```

## 主要依賴

- **GCDWebServer**: HTTP 服務器框架
- **Photos Framework**: macOS 照片庫存取
- **Foundation**: 基本功能框架
- **AppKit**: macOS UI 框架

## 權限設定

應用程式需要以下權限：

1. **照片庫存取權限** (Privacy - Photos Library Usage Description)
2. **網路權限** (用於本地 HTTP 服務器)

## 構建配置

### Debug 模式
```bash
swift build -c debug
```

### Release 模式
```bash
swift build -c release
```

## 執行與測試

### 1. 執行應用程式
```bash
# 從源碼執行
swift run

# 執行構建好的二進制檔案
./.build/debug/ObsidianPhotosBridge
```

### 2. 測試 API 端點
```bash
# 健康檢查
curl http://localhost:44556/api/health

# 獲取照片列表
curl http://localhost:44556/api/photos

# 搜尋照片
curl "http://localhost:44556/api/photos/search?q=vacation"
```

## 打包發佈

### 創建應用程式包
```bash
# 構建 Release 版本
swift build -c release

# 創建應用程式包結構
mkdir -p ObsidianPhotosBridge.app/Contents/MacOS
mkdir -p ObsidianPhotosBridge.app/Contents/Resources

# 複製執行檔案
cp ./.build/release/ObsidianPhotosBridge ObsidianPhotosBridge.app/Contents/MacOS/

# 創建 Info.plist 檔案
# (需要另外建立，包含權限聲明)
```

### Info.plist 範例
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ObsidianPhotosBridge</string>
    <key>CFBundleIdentifier</key>
    <string>com.obsidian.photos-bridge</string>
    <key>CFBundleName</key>
    <string>Obsidian Photos Bridge</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSPhotoLibraryUsageDescription</key>
    <string>This app needs access to your photo library to display and export photos for use in Obsidian.</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
```

## 故障排除

### 1. 編譯錯誤
- 確認 Xcode 版本符合需求
- 檢查 Swift 版本是否正確
- 清理並重新構建: `swift package clean && swift build`

### 2. 依賴問題
```bash
# 重新解析依賴
swift package resolve

# 更新依賴
swift package update
```

### 3. 權限問題
- 確保在 Info.plist 中正確聲明了照片庫存取權限
- 首次執行時會提示授權，需要使用者同意

### 4. 埠口被佔用
- 檢查 44556 埠口是否被其他應用程式使用
- 可在代碼中修改 `port` 變數使用其他埠口

## 開發建議

1. **使用 Xcode 進行開發** - 更好的除錯和 UI 設計支援
2. **定期測試權限流程** - 照片庫權限對應用程式功能至關重要
3. **監控記憶體使用** - 處理大量照片時注意記憶體管理
4. **測試不同 Photos.app 狀態** - 空庫、大量照片、不同媒體類型等

## 發佈清單

- [ ] 完成所有功能測試
- [ ] 驗證權限申請流程
- [ ] 測試在不同 macOS 版本上的相容性
- [ ] 創建應用程式圖標
- [ ] 準備應用程式簽名和公證
- [ ] 撰寫使用者安裝指南 