# LyricsFloat 測試版

[English](README.md) | [繁體中文](README.zh-TW.md)

Windows、macOS 與 Android 的動態歌詞原型。Windows／Android 讀取系統媒體資訊；macOS 透過「自動化」權限讀取 Spotify、Apple Music 或 YouTube Music 分頁。不需要連結 Spotify 帳號或 Premium。

## 已實作

- Windows 安裝版：新版安裝檔沿用相同位置並保留歌詞與設定。啟動時背景檢查更新，有新版可前往下載；設定中可關閉自動檢查或手動檢查。

- 提供繁體中文與英文介面，預設跟隨系統語言（中文系統使用繁體中文，其他語言使用英文）。可在「設定 → 介面語言」選擇「跟隨系統」、「繁體中文」或「English」，選擇會保存在本機；歌名與歌詞維持原文。
- 讀取目前歌曲、歌手、播放狀態與進度。Windows 使用 `Windows.Media.Control`，支援 Spotify 與主流桌面音樂軟體；Android 使用媒體工作階段；macOS 讀取 Spotify 桌面版、Apple Music 或 Chrome／Edge 的 YouTube Music 分頁。
- 貼上 LRC 動態歌詞，按歌曲名稱與歌手配對，播放時逐行顯示。
- 可指定只讀取 Spotify／桌面音樂軟體、YouTube／瀏覽器媒體或兩者；已顯示的歌曲可直接開啟歌詞編輯器，並為每首歌保存時間偏移。
- 歌詞庫沒有目前歌曲時，依序向網易雲音樂、酷狗音樂、LRCLIB、AMLL、LrcAPI 查找免費的動態歌詞；也可另外設定 Musixmatch 或騰訊雲音速達。自動過濾 Official MV、Remaster、Topic 等影片與版本雜訊，支援簡繁體雙向搜尋與放寬時長容差。找到後儲存到本機歌詞庫，也能經由 Wi-Fi 同步到另一台裝置。可在設定中勾選要使用的來源。搜尋失敗時可手動重試或貼上 LRC。
- Android 雙行歌詞浮窗：上行固定顯示目前唱到的一句並以黃色標示，下行預告下一句。可按住歌詞拖曳，右側 `×` 可快速關閉，重新開啟會保留位置。Windows／macOS 置頂精簡視窗採用相同的雙行顯示，可按 `×` 返回一般視窗。
- 歌詞庫：查看、編輯、複製 LRC。
- 手動新增或修改 LRC 後，可選擇公開發布到 LRCLIB，讓其他裝置也能搜尋到。發布前會顯示歌詞並要求確認專輯與歌曲長度；本機儲存不會自動公開。相同歌曲再次發布會成為新的修訂版本。
- 同一 Wi-Fi 下以 IP 和臨時八位配對碼雙向同步歌詞。兩台裝置都需開啟 App。
- 可連結 Google 帳號，將歌詞庫備份到 Google Drive 的 App 專屬隱藏資料夾。在每台裝置按「合併並同步」，會先合併雲端與本機歌詞，再更新雲端備份；不需在同一 Wi-Fi。
- 同步遇到內容不同的較新版本時，保留舊版本作為衝突備份。

## 試用

Android：大多數 Android 手機可安裝 `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`。首次開啟後按「授權讀取播放資訊」，在 Android 設定中啟用 LyricsFloat 的通知存取權。按右上角浮窗按鈕可開啟歌詞浮窗，Android 會另行要求「顯示在其他應用程式上層」權限。浮窗顯示時可按住歌詞區拖動，按右側 `×` 關閉。下拉快捷設定兩次、按編輯或鉛筆圖示，可將「浮動歌詞」開關拖入面板。舊版 APK 使用開發金鑰；從固定簽章版本開始可持續覆蓋升級。

主畫面右上角保留浮窗／桌面歌詞、手動搜尋、歌詞庫和設定。點「歌詞庫」可查看、編輯、匯入 LRC 或與另一台裝置同步。設定按播放與搜尋、歌詞顯示、Android 權限與快捷設定分組；在「App 內歌詞」可選 3、5、7 行，並將目前歌詞的字體大小調整為 18 至 40。這項設定保存在本機，只影響 App 內畫面；浮窗與桌面精簡視窗維持雙行。

Windows：新版 Release 會提供 `LyricsFloat-Windows-x64-Setup.exe`，安裝後可從開始選單開啟；更新時執行新版安裝檔，沿用同一安裝位置與本機資料。也保留 ZIP 免安裝版。自行編譯請照 [Windows 操作說明](WINDOWS-START.md)安裝 Flutter 與 Visual Studio C++ 桌面工具，於專案目錄執行 `flutter run -d windows`。播放 Spotify 或 YouTube Music 時，按右上角精簡視窗按鈕可顯示置頂歌詞。

macOS：安裝 Flutter、Xcode 與 CocoaPods，在專案目錄執行 `flutter pub get`、`flutter run -d macos --dart-define-from-file=.env.google-oauth.local.json`。也可執行 `flutter build macos --release --dart-define-from-file=.env.google-oauth.local.json`，成品位於 `build/macos/Build/Products/Release/lyrics_float.app`。按右上角精簡視窗按鈕可顯示置頂雙行歌詞，拖動視窗標題列即可移動；按 `×` 回到一般視窗。

首次讀取 Spotify 或瀏覽器時，請允許 macOS 顯示的「自動化」授權。若曾拒絕，到「系統設定 → 隱私權與安全性 → 自動化」重新允許 LyricsFloat 控制對應 App。使用 YouTube Music 時，請在 Chrome／Edge 的「檢視 → 開發人員」啟用「允許 Apple Events 執行 JavaScript」，並保持 `music.youtube.com` 分頁開啟。Mac 版目前支援這兩種瀏覽器的 YouTube Music 網頁，不讀取其他網站或獨立 PWA。Mac 與其他裝置可沿用下方的同一 Wi-Fi 歌詞同步功能。自行在本機建置試用不需要付費帳號；若要對外散布 Mac App，仍須處理 Apple 的簽署與公證程序。

## 在兩台電腦同步原始碼

另一台電腦首次使用時，先安裝 Git，再執行：

```powershell
git clone https://github.com/MrRice-TW/LyricsFloat.git
cd LyricsFloat
flutter pub get
```

之後開始工作前執行 `git pull`；修改程式後執行 `git add .`、`git commit -m "說明這次修改"` 和 `git push`。GitHub 同步的是原始碼；每台電腦本機歌詞庫與搜尋設定不會上傳到儲存庫，歌詞庫可用 App 內的「同步歌詞」功能傳到另一台裝置。

匯入：按右上角「歌詞庫」→「匯入 LRC」，填寫歌名與歌手，貼上例如：

```lrc
[00:12.50]第一句歌詞
[00:16.20]第二句歌詞
```

同步：兩台裝置連上同一 Wi-Fi，各自從「歌詞庫」→「同步」開啟同步對話框。在其中一台輸入另一台顯示的區域網路 IP 與配對碼，再按「立即同步」。Windows 首次執行時可能需要允許防火牆的私人網路存取。

Google 雲端同步：在「歌詞庫 → 雲端同步」或「設定 → Google 雲端備份」連結 Google 帳號，再按「合併並同步」。另一台裝置以同一帳號連結並同步即可取得歌詞。同步由使用者手動啟動；它會保留本機歌詞及衝突備份，不會清空歌詞庫。測試階段只有 `yuio0815@gmail.com` 在 OAuth 測試名單內；Google 測試模式的授權可能約七天後要求重新登入。Drive 的 App 專屬資料夾不會顯示在一般雲端硬碟檔案清單。

自行編譯 Windows／macOS 版的 Google 登入時，需在專案根目錄建立 Git 忽略的 `.env.google-oauth.local.json`，填入 Google Cloud 對應「電腦」OAuth 用戶端的 `GOOGLE_WINDOWS_CLIENT_SECRET`／`GOOGLE_MAC_CLIENT_SECRET`。例如執行 `flutter run -d macos --dart-define-from-file=.env.google-oauth.local.json`，或將 `run` 換成 `build macos --release`。Windows 將裝置改為 `windows`。GitHub Release 工作流程則從同名 Repository secrets 讀取。桌面 App 會內含用戶端密鑰，因此它不能被視為只有伺服器知道的秘密；Google 登入安全性仍依賴使用者同意、限定的 Drive 權限及 PKCE。

自動搜尋：播放音樂時，若系統提供歌名與歌手、歌詞庫沒有該曲，App 會依序查詢網易雲音樂、酷狗音樂、[LRCLIB](https://lrclib.net/)、[AMLL](https://amll.dev/reference/http-api/lrclib)、[LrcAPI](https://docs.lrc.cx/docs/legacy/lyrics/)。找到相符的 LRC 便自動儲存並顯示。程式會自動過濾 YouTube 標題的影片後綴與雜訊標籤，支援繁簡中文字互轉搜尋；若有歌曲長度，也會以合理的容差過濾明顯不合的版本。需要網路連線，不用 Spotify Premium 或歌詞 API 金鑰。

搜尋來源設定：點右上角齒輪 →「播放與搜尋」→「歌詞搜尋來源」，勾選要使用的網站並儲存。預設網易雲音樂、酷狗音樂、LRCLIB、AMLL、LrcAPI 皆開啟，依畫面順序搜尋；全部取消勾選即停止線上搜尋。設定儲存在這台裝置上，不會經由 Wi-Fi 同步；已匯入的歌詞不受影響。

手動搜尋：播放資訊已有歌曲、卻未找到歌詞時，按畫面中的「輸入歌名搜尋」，或按右上角放大鏡。對話框會自動預填清洗後的乾淨歌名和歌手，可修改後重新搜尋；各來源找到的動態歌詞會列出候選清單供挑選。按「試套用」後，歌詞會跟著目前播放進度顯示，但尚未寫入歌詞庫。確認內容與時間吻合後按「確認儲存」，不合則按「取消」或「換一份」。歌手尾碼與合作歌手會在搜尋與比對時智慧比對；程式也會嘗試簡體與繁體歌名。

### 選用歌詞來源

Musixmatch：先向 [Musixmatch 開發者平台](https://developer.musixmatch.com/)申請具同步歌詞存取權的 API key。啟動程式前將 `MUSIXMATCH_API_KEY` 設為該金鑰，重開程式，再到「歌詞搜尋來源」勾選 Musixmatch。程式會先核對歌名、歌手與可用的歌曲長度，才下載 LRC 同步歌詞。金鑰只從執行環境讀取，不存入本機設定檔。供應商方案、歌詞顯示、快取與分享權限須以你的合約為準。

騰訊雲音速達：需先向 [騰訊雲申請並通過使用場景審核](https://cloud.tencent.com/document/product/1592/77580)。官方目前列出的場景是直播、語聊、KTV 等即時互動房間；本程式作為其他音樂 App 的桌面歌詞浮窗，是否獲准使用必須先由騰訊雲確認。核准後，啟動前設定 `TENCENT_SECRET_ID`、`TENCENT_SECRET_KEY`、`TENCENT_YINSUDA_APP_NAME`、`TENCENT_YINSUDA_USER_ID`，重開程式，再勾選「騰訊雲音速達」。程式透過 [SearchKTVMusics](https://cloud.tencent.com/document/product/1592/76186) 與 [BatchDescribeKTVMusicDetails](https://cloud.tencent.com/document/api/1592/76190) 取得歌詞檔並轉為 LRC。這些密鑰也只從執行環境讀取；請勿放進原始碼或對外散布的安裝包。

這兩個來源預設關閉；憑證缺少時無法勾選。查詢可能產生供應商費用。程式目前會把取得的歌詞儲存在本機，並可經 Wi-Fi 同步；啟用前請確認你的授權允許這些用途。

公開分享：手動儲存歌詞後，點提示中的「發布到 LRCLIB」，或在歌詞庫點歌曲旁的發布圖示。確認專輯名稱、歌曲長度（秒）和歌詞內容後才會送出。專輯或長度不符時，LRCLIB 可能建立另一首歌，而不是同曲修訂。投稿驗證可能需稍等；驗證期間可取消。發布後 LRCLIB 的搜尋快取可能不會立刻更新。公開分享與同一 Wi-Fi 的私人同步是兩種獨立功能。

## 目前限制

- Google Drive 同步目前需手動執行；兩台裝置同時修改並同步同一首歌時，請檢查歌詞庫中的衝突備份。
- 音檔自動辨識與產生 LRC 尚未接入；可先手動貼上 LRC。
- Android 浮窗目前跟隨 App 程序，系統若清除背景程序，需重新開啟 App。
- Mac 版已在 Apple Silicon Mac 上編譯；Spotify／YouTube Music 實際讀取仍需在播放時授權並測試。Android 建置需另行安裝 Android SDK。
- 播放來源需對作業系統公開媒體資訊；若未公開，App 便無法偵測。
- LRCLIB、AMLL 與 LrcAPI 不保證每首歌都有動態歌詞；找不到時仍可手動匯入。LrcAPI 的公開服務可能較慢且結果不一定準確；App 會再檢查歌名、歌手及可用的長度資訊。外部歌詞會標示來源，不會自動公開投稿到 LRCLIB。

繁簡字匹配使用 [OpenCC 的 TSCharacters 字典](https://github.com/BYVoid/OpenCC/blob/master/data/dictionary/TSCharacters.txt)，依 Apache 2.0 授權；授權全文見 `assets/opencc/LICENSE`。

## 授權

LyricsFloat 採用 [MIT 授權](LICENSE)。內附 OpenCC TSCharacters 字典屬第三方素材，依 [Apache 2.0 授權](assets/opencc/LICENSE)提供。

## 開發檢查

```sh
flutter analyze
flutter test
flutter build apk --release --split-per-abi --target-platform android-arm64
```

## 統一發布

推送 `v*` 版本標籤時，GitHub Actions 會分別在 Windows、macOS、Linux 建置 Windows 可執行 ZIP、Mac App ZIP 與 Android arm64 APK，並在測試與三個平台建置都成功後，將三份檔案附到同一個 GitHub Release。要補建既有標籤，可在 GitHub「Actions → Build release packages → Run workflow」選擇 `main` 並輸入標籤名稱。完整版本說明維護於 [RELEASE_NOTES.md](RELEASE_NOTES.md)。[GitHub 官方說明](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)指出，公開儲存庫使用標準 GitHub 建置機不需付費。

Android 發行版現在要求 GitHub Actions 的 `ANDROID_KEYSTORE_BASE64` 與 `ANDROID_KEYSTORE_PASSWORD` Secrets；缺少任一項或 APK 憑證指紋不符時，流程會停止。私有金鑰與密碼不會進 Git。下次發布前請依照 [Android 固定簽章設定](android/SIGNING.md)完成 Secrets。`v1.2.3-beta` 及以前的 APK 使用臨時開發簽章，換用固定簽章的第一版前須備份歌詞、移除舊版後重裝一次；之後可用同一把金鑰直接覆蓋升級。Windows 提供免安裝 ZIP，解壓縮後執行 `lyrics_float.exe`；Mac ZIP 未經 Apple 公證。
