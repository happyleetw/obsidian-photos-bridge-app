# Obsidian Photos Bridge App

一個原生 macOS 應用程式，讓 Obsidian 能夠存取 Photos.app 中的照片和影片。

## 功能特色

- ✅ 存取 macOS Photos Library
- ✅ 提供本地 HTTP API 服務
- ✅ 支援照片/影片縮圖預覽
- ✅ 自動匯出媒體檔案到 Obsidian Vault
- ✅ 保護隱私，所有操作僅限本機

## 系統需求

- macOS 12.0 或更新版本
- Xcode 14.0 或更新版本
- Swift 5.7 或更新版本

## 安裝說明

1. 使用 Xcode 開啟專案
2. 首次執行時會要求照片存取權限
3. 應用程式會在 `http://localhost:44556` 啟動 API 服務

## API 端點

### GET /api/photos
取得所有照片/影片清單

```json
{
  "photos": [
    {
      "id": "photo-uuid",
      "filename": "IMG_1234.jpg",
      "createdDate": "2024-01-01T12:00:00Z",
      "modifiedDate": "2024-01-01T12:00:00Z",
      "mediaType": "image",
      "width": 4000,
      "height": 3000,
      "thumbnailUrl": "/api/thumbnails/photo-uuid"
    }
  ],
  "total": 1250
}
```

### GET /api/thumbnails/:id
取得指定照片的縮圖

### GET /api/photos/:id/original
取得指定照片的原始檔案

### POST /api/photos/:id/export
匯出照片到指定資料夾

```json
{
  "destination": "/path/to/vault/media/",
  "filename": "optional-custom-name.jpg"
}
```

## 開發說明

專案使用 Swift + Photos Framework + GCDWebServer 建置。

主要模組：
- `PhotosManager`: 管理 Photos Library 存取
- `APIServer`: HTTP API 服務器
- `FileExporter`: 檔案匯出功能
- `ThumbnailGenerator`: 縮圖生成

## 隱私聲明

此應用程式僅在本機處理照片資料，不會上傳或傳送任何照片內容到外部服務器。所有 API 呼叫僅限於本機 localhost 連線。 