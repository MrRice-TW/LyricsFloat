# LyricsFloat release notes

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
