# 在 Windows 執行 LyricsFloat

新版發行流程會提供 `LyricsFloat-Windows-x64-Setup.exe` 安裝檔。執行後預設安裝在 `%LOCALAPPDATA%\Programs\LyricsFloat`，可從開始選單開啟，也可選擇建立桌面捷徑。更新時關閉程式，再執行新版安裝檔，會沿用原本安裝位置，不需要每次解壓出新的資料夾。可從 Windows「已安裝的應用程式」解除安裝。

歌詞與設定儲存在 `%LOCALAPPDATA%\LyricsFloat`，更新與解除安裝不會刪除這份資料。原本使用 ZIP 版的使用者，在同一個 Windows 帳號安裝後也會沿用資料；確認安裝版可正常使用後，可自行刪除舊的解壓資料夾。

仍提供 `LyricsFloat-Windows-x64.zip` 免安裝版，完整解壓縮後執行 `lyrics_float.exe`，請保留同一資料夾內的 DLL 與 `data` 資料夾。Android 的 `.apk` 不能在 Windows 執行。

Windows 版預設在每次啟動後背景檢查 GitHub Release。有已提供 Windows 安裝檔的新版時，會顯示目前與最新版本，按「前往下載」開啟該版發行頁；下載 Setup.exe、關閉程式再執行即可更新。沒有網路或檢查失敗不會中斷播放。可在「設定」關閉「啟動時檢查更新」，或選「立即檢查更新」。測試版會包含較新的測試版；正式版只提示正式版。不會自動下載或執行安裝檔。

## 下載版點兩下沒有開啟

原先的 v1.2.7-beta Windows 套件使用 Flutter 3.38.5，放在含中文等非 ASCII 字元的路徑時可能立即崩潰，例如 `D:\下載\Compress\LyricsFloat-Windows-x64`。請將整個資料夾複製到純英文路徑，例如 `D:\LyricsFloat-Windows-x64`，再執行裡面的 `lyrics_float.exe`；不要只移動 EXE。

Flutter 3.38.6 已修復這個引擎問題，專案發行設定改用 3.38.10，並檢查中文路徑啟動。此設定需重新建置及發布後才會反映在 GitHub 下載套件中。詳見 [Flutter 修復紀錄](https://github.com/flutter/flutter/blob/master/CHANGELOG.md#3386)。

## 第一次準備

1. 安裝 Git 後執行 `git clone https://github.com/MrRice-TW/LyricsFloat.git`，取得 `LyricsFloat` 專案資料夾；裡面應有 `pubspec.yaml`、`lib` 和 `windows`。
2. 依 [Flutter 官方 Windows 安裝說明](https://docs.flutter.dev/install/manual)安裝 Flutter SDK，並將 Flutter 的 `bin` 資料夾加入 PATH。安裝後重新開啟 PowerShell。
3. 安裝 Visual Studio Community，勾選 **Desktop development with C++** 工作負載。這是 Visual Studio，不是 Visual Studio Code。詳見 [Flutter 的 Windows 開發設定](https://docs.flutter.dev/platform-integration/windows/setup)。

## 測試執行

開啟 PowerShell，進入解壓後的 `LyricsFloat` 資料夾，再依序執行：

```powershell
flutter doctor -v
flutter devices
flutter pub get
flutter run -d windows
```

`flutter doctor -v` 應能辨識 Windows 與 Visual Studio；`flutter devices` 應列出 Windows。這個專案只測試 Windows 桌面時，不必先準備 Android SDK。

App 開啟後，播放 Spotify 或瀏覽器中的 YouTube Music。偵測到歌曲後會自動搜尋動態歌詞。右上角的精簡視窗按鈕可顯示置頂雙行歌詞；齒輪 →「歌詞搜尋來源」可勾選搜尋網站。首次使用同一 Wi-Fi 同步時，若 Windows 防火牆詢問，允許私人網路存取。

## 建立可直接開啟的版本

在同一個專案資料夾執行：

```powershell
flutter build windows --release
```

一般 x64 Windows 電腦上的執行檔位置是 `build\windows\x64\runner\Release\lyrics_float.exe`。要搬到另一台 Windows 電腦，需複製整個 `Release` 資料夾，保留其中的 DLL 與 `data` 資料夾；只有 `.exe` 不夠。這是 [Flutter 官方 Windows 打包說明](https://docs.flutter.dev/platform-integration/windows/building)所要求的結構。

此專案已在 Windows 實機編譯與試播。若執行時出現錯誤，請保留 PowerShell 顯示的完整訊息，以便定位問題。

## 建立 Windows 安裝檔

先完成 Windows release 建置，再安裝 Inno Setup 6，執行以下指令（版本請與 `pubspec.yaml` 一致，不含 `+` 後的建置編號）：

```powershell
& 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe' '/DAppVersion=1.2.9-beta' windows/installer/LyricsFloat.iss
```

成品為 `dist\LyricsFloat-Windows-x64-Setup.exe`。GitHub Release 工作流程會自動讀取版本並建立安裝檔與 ZIP。
