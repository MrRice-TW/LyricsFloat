# iOS Spotify 預覽版

iOS 專案目前是開發預覽：以 Spotify 官方 App Remote SDK 接收歌名、歌手與播放進度，在 LyricsFloat 內搜尋並顯示動態歌詞。需要 iPhone 已安裝 Spotify 並登入，使用者按「連接 Spotify」授權。Spotify 授權流程可能繼續播放上一首歌曲。

## 目前支援範圍

- App 內動態歌詞、歌詞搜尋來源、匯入 LRC、歌詞庫與同一 Wi-Fi 同步。
- 繁體中文與英文介面。
- App 進入背景時會斷開 Spotify Remote，返回前景後嘗試重連。不提供 Android 的跨 App 浮窗、通知讀取、快捷設定功能。
- Google Drive 備份尚未配置 iOS OAuth，因此 iOS 不顯示雲端備份入口。
- 尚無 iOS 發行下載檔，不使用 GitHub APK／桌面安裝檔的更新檢查。未來經 TestFlight／App Store 發布後，更新由該通路提供。
- 沒有設定 Spotify Client ID 的建置仍可使用本機歌詞庫與 Wi-Fi 同步，會說明 Spotify 尚未設定，不會嘗試登入。

## Spotify 設定

在 [Spotify Developer Dashboard](https://developer.spotify.com/dashboard) 建立 App，設定：

- Bundle ID：`com.lyricsfloat.lyricsFloat`
- Redirect URI：`lyricsfloat-spotify://callback`
- SDK：iOS
- 將測試帳號加入該 Spotify App 允許的使用者名單（如 App 在開發模式）。

編譯時傳入公開的 `SPOTIFY_IOS_CLIENT_ID`；不要將 Client Secret 放進手機 App。SDK 固定為官方 iOS SDK v3.0.0，由 CocoaPods 取得，詳見 [Spotify 官方設定說明](https://developer.spotify.com/documentation/ios/getting-started)。

## 自己的 iPhone 測試

需有 Mac、Xcode、Flutter 與 CocoaPods。在 Mac 的專案目錄：

```sh
flutter pub get
open ios/Runner.xcworkspace
```

在 Xcode 的 Runner → Signing & Capabilities 選擇自己的 Team，連接 iPhone，依系統提示開啟 Developer Mode。若個人簽章需要不同的 Bundle ID，也要同步修改 Spotify Dashboard 的 Bundle ID。然後執行：

```sh
flutter run -d <iPhone裝置ID> --dart-define=SPOTIFY_IOS_CLIENT_ID=<你的ClientID>
```

Personal Team 可供個人裝置開發測試，並受 Apple 的簽章與有效期限限制。對外提供 TestFlight／App Store 版本則需要 Apple Developer Program 帳號與簽章設定。

## 建置驗證

GitHub 的 `Verify iOS preview` 流程在 macOS 上執行程式檢查、測試、未簽章實機建置與模擬器建置。不會發布 IPA；未簽章 App 無法直接安裝到一般 iPhone。可將公開 Client ID 設定為 Repository secret `SPOTIFY_IOS_CLIENT_ID` 供驗證流程使用。

建置通過不等於 Spotify 真機測試完成。Spotify 登入、播放狀態及前背景切換仍需在設定了 Client ID 的 iPhone 上驗證。
