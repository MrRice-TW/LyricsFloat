# LyricsFloat release notes

## v1.1.0-beta — macOS preview (2026-09-29)

### English

- Added a macOS app with a movable, always-on-top two-line lyrics window.
- Read the current track and playback position from the Spotify desktop app or YouTube Music tabs in Chrome and Edge. When several supported sources are open, prefer a playing track.
- Kept the existing lyric library, online lookup, manual LRC import, per-song timing adjustment, and same-Wi-Fi sync on macOS.
- Added macOS setup and permission instructions to both READMEs.

**Try it on a Mac:** Download and unzip `LyricsFloat-macOS.zip`, then open `lyrics_float.app`. Allow macOS Automation access to Spotify or the browser when prompted. For YouTube Music, enable **View → Developer → Allow JavaScript from Apple Events** in Chrome or Edge and keep a `music.youtube.com` tab open. The app can also be built locally with `flutter run -d macos`.

**Preview limitations:** The macOS app builds successfully and the existing 27 tests pass, but Spotify and YouTube Music playback have not yet been verified with a live song and the required permissions. The ZIP is a locally signed, unnotarized preview; macOS may warn when opening a downloaded copy. Standalone YouTube Music PWAs and other browser sites are not supported by the macOS reader.

### 繁體中文

- 新增 macOS App，提供可移動、置頂的雙行歌詞視窗。
- 支援讀取 Spotify 桌面版，以及 Chrome／Edge 中 YouTube Music 分頁的歌曲與播放進度；同時開啟多個來源時，優先顯示正在播放的歌曲。
- Mac 版沿用原有歌詞庫、線上搜尋、手動匯入 LRC、單曲時間偏移，以及同一 Wi-Fi 歌詞同步。
- 在中英文 README 加入 Mac 安裝與授權步驟。

**試用方式：**下載並解壓縮 `LyricsFloat-macOS.zip`，開啟 `lyrics_float.app`。首次讀取時允許 macOS 的「自動化」權限。使用 YouTube Music 前，請在 Chrome／Edge 的「檢視 → 開發人員」開啟「允許 Apple Events 執行 JavaScript」，並保持 `music.youtube.com` 分頁開啟。也可以在專案目錄執行 `flutter run -d macos` 自行建置。

**測試版限制：**Mac App 已完成編譯，原有 27 個測試均通過；Spotify 與 YouTube Music 的實際播放讀取仍待播放歌曲並授權後驗證。ZIP 是本機簽署、未經 Apple 公證的測試版，從網路下載後 macOS 可能顯示警告。Mac 版尚不支援獨立 YouTube Music PWA 或其他網站。
