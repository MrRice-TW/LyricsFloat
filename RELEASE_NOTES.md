# LyricsFloat release notes

## v1.2.9-beta — Windows memory leak fix and cross-platform update checks (2026-10-04)

### 繁體中文

- 修復 Windows 長時間播放後記憶體、執行緒與系統資源持續累積的問題。播放偵測改成重用單一背景工作執行緒與媒體連接，並在結束時釋放 Windows Runtime 資源；媒體查詢加入逾時處理。
- 發行流程新增持續輪詢的記憶體、執行緒與控制代碼累積檢查。
- Android、macOS 補上啟動時及手動檢查更新，各自確認對應的 APK／macOS ZIP 已上傳才提示，並顯示適合該平台的更新步驟。可在設定關閉自動檢查。
- 原始碼新增 iOS Spotify 開發預覽，未簽章 iPhone 與模擬器建置已通過。需要 Spotify Client ID 與真機測試，尚無可安裝的 iOS 發行下載檔；詳見 `IOS-START.md`。

**Windows 更新提醒：**關閉舊版再執行新版安裝檔。已累積的記憶體需在舊程序結束後才會釋放；歌詞與設定沿用原本資料。

### English

- Fixed accumulating Windows memory, threads and system resources during long-running playback. Polling now reuses one background worker and media session manager, balances Windows Runtime initialization on shutdown, and times out media queries.
- Added a sustained-polling memory/thread/handle accumulation check to the release workflow.
- Added startup and manual update checks on Android and macOS, requiring an uploaded APK or macOS ZIP respectively and showing platform-specific update instructions. Automatic checks can be disabled in Settings.
- Added an iOS Spotify development preview in source, with successful unsigned device and simulator builds. It still needs a Spotify Client ID and physical-device testing; no installable iOS release is distributed. See `IOS-START.md`.

**Windows update:** Close the previous app before running the new installer. Previously accumulated memory is released when the old process exits. Lyrics and settings are preserved.

## v1.2.8-beta — Windows installer, update checks and interface languages (2026-10-04)

### 繁體中文

- Windows 新增 `LyricsFloat-Windows-x64-Setup.exe` 安裝版，提供開始選單捷徑、選用桌面捷徑及解除安裝。後續執行新版安裝檔會沿用原本位置，不必每次解壓出新資料夾；仍保留 ZIP 免安裝版。
- 歌詞與設定沿用 `%LOCALAPPDATA%\LyricsFloat`，同一 Windows 帳號從 ZIP 版改用安裝版不需搬移資料。更新與解除安裝不會刪除這份資料。
- Windows 啟動後會在背景檢查 GitHub Release，有已提供安裝檔的新版時顯示通知並可開啟下載頁。可在設定關閉自動檢查或立即手動檢查；測試版也會檢查較新的測試版。下載後關閉 App，再執行新版安裝檔。離線或檢查失敗不會中斷播放。
- 新增繁體中文與英文介面，預設跟隨系統語言，可在設定切換並記住選擇；歌名與歌詞維持原文。
- Windows 套件附上 MSVC 執行元件，並驗證中文路徑啟動、安裝、重複安裝更新及解除安裝。

### English

- Added `LyricsFloat-Windows-x64-Setup.exe` with Start menu shortcuts, an optional desktop shortcut and uninstall support. New installers reuse the existing installation directory. The portable ZIP remains available.
- Lyrics and settings remain in `%LOCALAPPDATA%\LyricsFloat`, allowing migration from the ZIP under the same Windows account. Upgrades and uninstall preserve this data.
- Windows checks GitHub releases in the background at startup and offers a download page when a newer installer is available. Settings includes an opt-out and a manual check. Beta builds include newer beta releases. Close the app before running the downloaded installer; offline or failed checks do not interrupt playback.
- Added Traditional Chinese and English interfaces, following the system language by default with a saved language choice in Settings. Song titles and lyrics retain their original text.
- Windows packages now include MSVC runtime libraries. Installation, repeated-install upgrades, Unicode-path startup and uninstall have been verified.

## v1.2.7-beta — Windows display polish and Drive sync verification (2026-10-02)

### English

- Show **Spotify** instead of its Windows media session identifier in the playback status.
- Show **LyricsFloat** as the Windows window title.
- Verified Google Drive backup on Windows with the v1.2.6-beta release: the first merge imported 154 songs for a total of 206, a repeat imported none, and sync still worked after restarting the app. This release keeps the same backup flow.

### 繁體中文

- Windows 播放狀態改為顯示「Spotify」，不再顯示系統提供的內部識別碼。
- Windows 視窗標題改為「LyricsFloat」。
- 已用 v1.2.6-beta 發行版驗證 Windows 的 Google 雲端備份：首次合併匯入 154 首、共 206 首；再次同步未重複匯入，重新啟動後仍可同步。本版沿用相同的備份流程。

## v1.2.6-beta — Android Google Drive sign-in test (2026-10-02)

### English

- Changed Android Google Drive connection to request Drive authorization directly. This avoids the separate Credential Manager sign-in step that reported `[16] Account reauth failed` after account selection on a Pixel 10 Pro running Android 17.
- The app remembers the connected Drive account and checks its identity before each sync, preventing a silent account switch from sending lyrics to another Drive.
- Renamed the local disconnect action to **Disconnect**. The Windows and macOS backup flows are unchanged.

**Testing note:** Android 17 sign-in still needs verification on the affected phone. Install the signed Android APK from this release over v1.2.5-beta, then connect Google and run **Merge and sync**. All three platform packages are included.

### 繁體中文

- Android 改為直接請求 Google Drive 授權，避開 Pixel 10 Pro／Android 17 在選完帳號後出現 `[16] Account reauth failed` 的獨立登入步驟。
- App 會記住已連結的 Drive 帳號，並在每次同步前核對，避免系統悄悄切換帳號後將歌詞傳到其他雲端硬碟。
- 本機連結操作改稱「中斷連結」。Windows 與 macOS 的備份流程維持原樣。

**測試提醒：**仍需在發生問題的 Android 17 手機上驗證。請使用此版正式簽章 APK 覆蓋安裝 v1.2.5-beta，連結 Google 後執行「合併並同步」。本版同時附上三平台檔案。

## v1.2.5-beta — Google Drive lyric backup (2026-10-02)

### English

- Added manual Google Drive backup for the lyric library on Android, Windows, and macOS. **Merge and sync** downloads the existing backup, keeps conflicting versions, and uploads the merged library to the app's private Drive data folder.
- Fixed desktop Google sign-in token exchange and macOS Keychain storage. The macOS sign-in and repeat sync were tested with a 139-song library.
- Release builds use GitHub Actions repository secrets for the Windows and macOS OAuth client configuration. The desktop client values are included in the built apps; Google access remains limited by user consent and the app data scope.
- All three platform packages are built and attached together when the release workflow succeeds.

**Testing note:** Google OAuth currently allows only the configured test account. Users outside the test list cannot connect until the OAuth app is published or added to the test list. Sync is manual.

### 繁體中文

- Android、Windows、macOS 新增手動 Google Drive 歌詞庫備份。「合併並同步」會下載既有備份、保留衝突版本，再將合併後的歌詞庫上傳到 App 專用的隱藏資料夾。
- 修復桌面版 Google 登入權杖交換與 macOS Keychain 儲存問題；已在 macOS 以 139 首歌詞測試登入及重複同步。
- 發行建置從 GitHub Actions Repository secrets 讀取 Windows／macOS OAuth 用戶端設定。桌面版成品會包含用戶端值；Google 存取仍受使用者同意與 App 專用資料夾權限限制。
- 發行流程成功時會一併附上 Windows、macOS、Android 三平台成品。

**測試提醒：**Google OAuth 目前僅允許已設定的測試帳號登入。其他使用者需加入測試名單或等 OAuth App 正式發布；同步需手動執行。

## v1.2.4-beta — Lyric display, simpler controls, and permanent Android signing (2026-10-02)

### English

- The main app view can show 3, 5, or 7 timed lyric lines. The current line remains prominent, and the surrounding lines provide context.
- Added **App 內歌詞顯示** in Settings to adjust the current line's font size from 18 to 40. The choice is saved locally and does not change the two-line overlay or compact desktop window.
- Reorganized the main toolbar around the overlay toggle, manual search, lyric library, and settings. Import and Wi-Fi sync are now in the lyric library; settings are grouped by purpose.
- Android releases use a permanent signing certificate. The release workflow stops if signing secrets are missing or the APK certificate fingerprint differs.

**One-time Android migration:** APKs through `v1.2.3-beta` used temporary debug keys. Back up or sync personal lyrics, uninstall the previous APK, and install this version once. Later versions signed with the same permanent key can upgrade in place.

### 繁體中文

- App 主畫面可顯示 3、5、7 行動態歌詞；目前唱到的一行保持醒目，前後歌詞提供上下文。
- 設定新增 **App 內歌詞顯示**，目前歌詞字體大小可在 18 至 40 間調整並保存在本機；雙行浮窗與桌面精簡視窗不受影響。
- 主畫面保留浮窗開關、手動搜尋、歌詞庫與設定；匯入和 Wi-Fi 同步移至歌詞庫，設定依用途分組。
- Android 發行版改用永久憑證簽署。缺少金鑰或 APK 憑證指紋不符時，發行流程會停止。

**Android 首次換版提醒：**`v1.2.3-beta` 及以前使用臨時測試簽章。請先備份或同步個人歌詞，移除舊 APK，再安裝此版一次。之後使用相同永久金鑰簽署的版本可以直接覆蓋升級。

## v1.2.3-beta — Android Quick Settings lyrics switch (2026-10-01)

### English

- Added an Android Quick Settings tile named **浮動歌詞**. Add it from the Quick Settings edit screen, then tap it to show or hide the floating lyrics window without searching for the app.
- The tile reflects whether the overlay is visible. If the app is not open, tapping the tile launches it and moves it to the background after showing the overlay. The first tap may open Android's overlay permission screen.
- Added a short setup guide in the Android app's settings menu.
- Windows and macOS packages are built alongside the Android APK for this release.

**Android upgrade note:** APKs are still signed with a build-machine debug key, which may differ from previous releases. Back up or sync your personal lyrics before replacing an installed APK.

### 繁體中文

- 新增 Android 快捷設定的 **浮動歌詞** 開關。從快捷設定編輯畫面加入後，點一下即可顯示或關閉浮動歌詞，不必再尋找 App。
- 開關狀態會跟浮窗同步。App 未開啟時，按鈕會啟動 App、顯示浮窗後切回背景；首次使用可能先開啟 Android 浮窗授權畫面。
- Android App 的設定選單新增加入快捷設定的操作說明。
- 本版同時提供 Windows、macOS 與 Android 檔案。

**Android 升級提醒：**APK 目前仍使用建置機的測試簽章，可能與前一版不同。更換已安裝的 APK 前，請先備份或同步個人歌詞。

## v1.2.2-beta — 修復 macOS Spotify 歌曲長度單位解析錯誤 (2026-09-29)

### English

- **Fixed Spotify duration calculation on macOS**: Corrected an issue where Spotify's AppleScript returns `duration of song` in milliseconds (unlike `player position` which is in seconds). The previous code multiplied it by 1000 again, causing songs to register with a 68-hour duration (`246,000,000 ms`), causing both automatic search and duration proximity ranking to reject matches.
- **Defensive duration normalization in Flutter**: Added runtime safeguards to auto-normalize overly large duration values across all platforms.

### 繁體中文

- **修復 macOS 平台 Spotify 歌曲長度單位解析錯誤**：Spotify 的 AppleScript 回傳的 `duration of song` 實際上已為毫秒（與秒單位的 `player position` 不同），原先代碼重複乘上了 1000，導致一首 4 分鐘的歌被計算成 68 小時（`246,000,000 毫秒`）。這導致後台自動搜尋比對時因時長差異過大而全部被判定不吻合（手動搜尋時顯示「相差 245754 秒」）。現已修正該數值解析，Spotify 播放時背景自動搜尋即可秒速匹配正確歌詞！
- **Flutter 端歌曲長度防禦校正**：加入防呆校驗邏輯，自動識別並校正因平台端重複乘算產生的極端時長數值。

## v1.2.1-beta — 背景自動搜尋二階段降級比對最佳化 (2026-09-29)

### English

- **Two-stage automatic background lyrics lookup**:
  - **Stage 1 (Exact Match)**: Searches with title, artist, and duration for primary exact matches.
  - **Stage 2 (Smart Fallback)**: If Stage 1 finds no match and the playback duration is known, the background search automatically falls back to querying all enabled sources by cleaned song title alone, picking the candidate with the closest duration within a 5-second tolerance.
- **Resilient to metadata differences**: Seamlessly resolves cases where YouTube channel names, publisher labels, or collaborator/cover artist variations caused the background search to miss lyrics (e.g. Joey Yung vs Silence Wang for 《就让这大雨全都落下》).
- **Support for tracks without artist tags**: Allows automatic lookup for media sources reporting only title and duration.

### 繁體中文

- **背景自動搜尋「二階段智慧降級比對」**：
  - **第 1 階段（精確比對）**：以「原曲名 + 歌手 + 時長」搜尋，優先鎖定正確歌手的歌詞。
  - **第 2 階段（自動降級比對）**：若第 1 階段未找到歌詞，且播放曲目有時長資訊，後台自動轉為「純歌名」向所有開啟的歌詞來源檢索，並自動挑選「歌曲長度最接近（公差 5 秒以內）」的動態歌詞直接套用！
- **自動克服歌手標籤不一致問題**：徹底解決 YouTube 頻道名、發行商標籤、合作歌手或翻唱者名稱差異導致背景搜尋落空的問題（如《就让这大雨全都落下》容祖兒 vs 汪蘇瀧）。
- **支援無歌手標籤之播放來源**：即使播放器未回傳歌手名稱，只要包含歌名與播放長度，背景也能自動完成歌詞匹配。

## v1.2.0-beta — 酷狗歌詞源、繁簡雙向轉換與智慧時長搜尋最佳化 (2026-09-29)

### English

- **Added Kugou Music (酷狗音樂) lyrics provider**: Supports candidate search and Base64-decoded synced LRC downloading, significantly increasing Mandarin music coverage.
- **Bidirectional Simplified & Traditional Chinese conversion**: Integrated OpenCC character mapping for titles and artists across all providers, matching Chinese songs seamlessly regardless of character variants.
- **Artist aliases & cross-language matching**: Built-in alias dictionary matching English/Chinese artist names (e.g. Joey Yung ↔ 容祖兒, Silence Wang ↔ 汪蘇瀧, Jay Chou ↔ 周杰倫, G.E.M. ↔ 鄧紫棋).
- **Studio vs Live version distinction**: Prevents studio tracks from accidentally matching live or acoustic versions with different timings.
- **Enhanced manual search dialog**:
  - Automatically queries by song title on open without requiring manual clicks.
  - Leaves the artist field blank by default (with a helpful hint) to avoid failing searches due to noisy or differing artist tags.
  - Lifts duration tolerance filters during manual search so all versions (24+ candidates for popular songs) are returned across enabled providers.
  - Automatically sorts search results by duration proximity to the currently playing audio, highlighting the closest match with `(長度相符 · 推薦)`.
- **Fixed desktop ESC crash**: Refactored the manual search dialog into a dedicated stateful widget, fixing the framework assertion crash (`_dependents.isEmpty`) caused by premature text controller disposal during dialog pop transitions.
- **macOS Apple Music support**: Added native Apple Music playback tracking on macOS.

### 繁體中文

- **新增「酷狗音樂」歌詞來源**：支援候選歌曲搜尋與 Base64 動態 LRC 下載解析，大幅提升華語流行歌曲的命中率。
- **繁簡中文雙向自動轉換**：整合 OpenCC 繁簡字元庫，在查詢與比對時自動轉換歌名與歌手，徹底解決繁簡不相符導致搜尋落空的問題。
- **歌手別名庫與跨語言比對**：內建常用華語歌手別名庫（如 容祖兒 ↔ Joey Yung、汪蘇瀧 ↔ Silence Wang、周杰倫 ↔ Jay Chou、鄧紫棋 ↔ G.E.M. 等），跨越中英文藝名障礙。
- **智慧過濾錄音室版與 Live 版**：嚴格辨識錄音室單曲與 Live / Acoustic / 演唱會版本，防止播放錄音室音檔時誤套用節奏不同的 Live 歌詞。
- **手動搜尋視窗體驗全面升級**：
  - 開啟視窗時自動以純歌名發動搜尋，無須手動點擊「搜尋」。
  - 歌手欄位預設留空（保留灰字提示），避免因播放來源歌手標籤吵雜（如頻道名、發行商、合作歌手）而導致全無結果。
  - 手動搜尋不再受限於播放時長公差，可一次檢索所有來源的所有版本歌詞（熱門歌曲可查出 24 筆以上候選）。
  - 搜尋結果自動依與當前播放秒數的差距由小到大排序，最接近的版本直接排在最上方並標記「長度相符 · 推薦」，一鍵試套用。
- **修復桌面端按 ESC 崩潰問題**：重構手動搜尋對話框為獨立 StatefulWidget，解決在退出動畫中提前銷毀 TextEditingController 觸發的 `assert(_dependents.isEmpty)` 紅畫面錯誤。
- **支援 macOS Apple Music**：新增 macOS 平台 Apple Music 桌面播放狀態追蹤。

## v1.1.0-beta — macOS preview (2026-09-29)

### English

- Added a macOS app with a movable, always-on-top two-line lyrics window.
- Read the current track and playback position from the Spotify desktop app or YouTube Music tabs in Chrome and Edge. When several supported sources are open, prefer a playing track.
- Kept the existing lyric library, online lookup, manual LRC import, per-song timing adjustment, and same-Wi-Fi sync on macOS.
- Added macOS setup and permission instructions to both READMEs.

**Try it on a Mac:** Download and unzip `LyricsFloat-macOS.zip`, then open `lyrics_float.app`. Allow macOS Automation access to Spotify or the browser when prompted. For YouTube Music, enable **View → Developer → Allow JavaScript from Apple Events** in Chrome or Edge and keep a `music.youtube.com` tab open. The app can also be built locally with `flutter run -d macos`.

**Preview limitations:** The macOS app builds successfully and the existing 27 tests pass, but Spotify and YouTube Music playback have not yet been verified with a live song and the required permissions. The ZIP is a locally signed, unnotarized preview; macOS may warn when opening a downloaded copy. Standalone YouTube Music PWAs and other browser sites are not supported by the macOS reader.

The unified release workflow also builds a Windows portable ZIP and Android arm64 APK. Android still uses a build-machine debug signing key, so back up lyrics before replacing a previous APK; seamless upgrades need a fixed signing key.

### 繁體中文

- 新增 macOS App，提供可移動、置頂的雙行歌詞視窗。
- 支援讀取 Spotify 桌面版，以及 Chrome／Edge 中 YouTube Music 分頁的歌曲與播放進度；同時開啟多個來源時，優先顯示正在播放的歌曲。
- Mac 版沿用原有歌詞庫、線上搜尋、手動匯入 LRC、單曲時間偏移，以及同一 Wi-Fi 歌詞同步。
- 在中英文 README 加入 Mac 安裝與授權步驟。

**試用方式：**下載並解壓縮 `LyricsFloat-macOS.zip`，開啟 `lyrics_float.app`。首次讀取時允許 macOS 的「自動化」權限。使用 YouTube Music 前，請在 Chrome／Edge 的「檢視 → 開發人員」開啟「允許 Apple Events 執行 JavaScript」，並保持 `music.youtube.com` 分頁開啟。也可以在專案目錄執行 `flutter run -d macos` 自行建置。

**測試版限制：**Mac App 已完成編譯，原有 27 個測試均通過；Spotify 與 YouTube Music 的實際播放讀取仍待播放歌曲並授權後驗證。ZIP 是本機簽署、未經 Apple 公證的測試版，從網路下載後 macOS 可能顯示警告。Mac 版尚不支援獨立 YouTube Music PWA 或其他網站。

統一發布流程也會產出 Windows 免安裝 ZIP 與 Android arm64 APK。Android 目前仍使用建置機的測試簽章，更換舊版前請先備份歌詞；若要直接覆蓋升級，需要設定固定的發布簽章。
