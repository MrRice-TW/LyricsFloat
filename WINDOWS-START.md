# 在 Windows 執行 LyricsFloat

目前提供的是 Flutter 原始專案。Android 的 `.apk` 不能在 Windows 執行；Windows 版需先在 Windows 電腦編譯一次。

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
