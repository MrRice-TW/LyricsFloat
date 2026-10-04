# LyricsFloat

[English](README.md) | [繁體中文](README.zh-TW.md)

Windows releases include `LyricsFloat-Windows-x64-Setup.exe` alongside the portable ZIP. Run a newer installer to update the same installation and keep your lyrics/settings. Windows, Android and macOS check for updates in the background at startup; Settings lets you turn this off or check manually. Notifications require a ready download for the current platform and show the corresponding installation instructions. Beta builds also check for newer beta releases; stable builds only offer stable releases.

An iOS Spotify development preview is available in source, with App Remote integration and local lyrics/Wi-Fi sync. It has not been distributed or tested against Spotify on a physical iPhone. It requires a Mac, Xcode, a Spotify Client ID and an iPhone. Lyrics appear while the app is in the foreground; iOS cloud backup is not configured. See [iOS setup](IOS-START.md).

LyricsFloat is an early-stage Flutter app for Windows, macOS, and Android that displays synchronized lyrics for music playing in other apps. Windows and Android read system media sessions; macOS uses user-approved automation to read Spotify or YouTube Music browser tabs. No Spotify account linking or Premium subscription is needed.

## Features

- English and Traditional Chinese interfaces follow the system language by default (Chinese systems use Traditional Chinese; other languages use English). Choose Follow system, 繁體中文, or English in Settings → Interface language. Your selection is saved locally; song titles and lyrics retain their original text.
- Displays the current, previous, and next lyric lines in the main window. Android offers a movable two-line overlay; Windows and macOS offer compact always-on-top lyrics windows.
- Reads song title, artist, playback state, and position from Windows Media Control, Android media sessions, the macOS Spotify or Apple Music app, or YouTube Music tabs in Chrome or Edge on macOS.
- Lets users select Spotify/desktop music players, YouTube/browser media, or both as playback sources. Windows and Android cannot limit browser media to a particular website because the system does not provide the tab URL; macOS reads only `music.youtube.com` tabs.
- Searches NetEase Cloud Music, Kugou Music, LRCLIB, AMLL, and LrcAPI for matching timed LRC lyrics. Automatically cleans YouTube title noise and supports bidirectional Simplified/Traditional Chinese matching. Musixmatch and Tencent Yinsuda are optional sources that require users' own credentials and may have provider costs.
- Offers manual search with duration proximity sorting, a live preview before saving, a quick editor for the current song, and a persistent timing adjustment for each song.
- Stores lyrics locally and supports manual two-way library sync over the same Wi-Fi network. Edited lyrics can be submitted to LRCLIB only after explicit confirmation.

## Get started

Install Flutter and the platform tools for the device you want to build for. Windows builds require Visual Studio with the **Desktop development with C++** workload. Android builds require the Android SDK. The [Windows setup guide](WINDOWS-START.md) has additional instructions in Chinese.

Clone the repository and fetch dependencies:

    git clone https://github.com/MrRice-TW/LyricsFloat.git
    cd LyricsFloat
    flutter pub get

Run on Windows:

    flutter run -d windows

Run on a connected Android device:

    flutter run -d android

Run on macOS (requires Flutter, Xcode, and CocoaPods):

    flutter run -d macos --dart-define-from-file=.env.google-oauth.local.json

Build a local macOS release app:

    flutter build macos --release --dart-define-from-file=.env.google-oauth.local.json

The app is created at `build/macos/Build/Products/Release/lyrics_float.app`. On first use, allow LyricsFloat to automate Spotify, Apple Music, or your browser. If you previously denied access, update it in **System Settings → Privacy & Security → Automation**. For YouTube Music, turn on **View → Developer → Allow JavaScript from Apple Events** in Chrome or Edge and keep a `music.youtube.com` tab open. The compact lyrics window can be moved by its title bar. Local builds do not require a paid Apple account; distribution to other Macs requires Apple signing and notarization.

On Android, grant notification access so the app can read active media sessions. The floating lyrics overlay also requires permission to display over other apps. Use the overlay button in the top bar to show or hide it. To add its Quick Settings switch, swipe down twice, tap the edit/pencil button, and drag **浮動歌詞** into the panel. Tap the tile to show or hide the overlay; it can launch LyricsFloat when the app is not open. The settings sheet also shows these steps. On Windows, allow private-network firewall access if you plan to sync lyrics over Wi-Fi.

The top bar keeps the overlay or compact-window toggle, manual search, lyric library, and settings close at hand. Open **歌詞庫** to view and edit saved lyrics, import LRC, or sync with another device. Settings are grouped by playback and search, lyric display, and Android permissions. Under **歌詞顯示 → App 內歌詞**, select 3, 5, or 7 visible lyric lines and adjust the current line's font size from 18 to 40. This setting is saved locally and applies to the main app view; the compact desktop window and Android overlay retain their two-line layout.

## Use lyrics

When a supported player exposes a song title and artist, LyricsFloat checks the local library first, then searches the enabled online lyric sources. It accepts matching timed lyrics and avoids automatically choosing between ambiguous versions. Simplified and Traditional Chinese titles and artist aliases are supported, and a trailing “- Topic” artist label is ignored during matching.

If the automatic search misses a song, use **Search by song name** to find candidates across all enabled providers. The dialog defaults to clean title search with candidate versions sorted by duration proximity so you can quickly pick the best match. Choose a result to preview it against the current playback position, then save it only if the lyrics and timing match. You can also import an LRC file or paste timed lines such as:

    [00:12.50]First lyric line
    [00:16.20]Second lyric line

Use **Edit current lyrics** to open the song being displayed without searching the library. The timing controls move lyrics in 0.5-second steps and save the adjustment for that song.

The settings sheet controls both playback sources and online lyric sources. The free lookup sources (NetEase, Kugou, LRCLIB, AMLL, LrcAPI) are enabled by default. Disabling every online lyric source stops automatic lookup without deleting saved lyrics.

## Optional lyric providers

Musixmatch requires a developer key with access to synchronized lyrics. Set the MUSIXMATCH_API_KEY environment variable before launching the app, then enable Musixmatch under lyric sources.

Tencent Yinsuda requires an approved use case and provider credentials. Set TENCENT_SECRET_ID, TENCENT_SECRET_KEY, TENCENT_YINSUDA_APP_NAME, and TENCENT_YINSUDA_USER_ID before launching the app, then enable Tencent Yinsuda. Confirm that your provider agreement permits lyric display, local storage, and sharing before use. Both optional providers are disabled by default. Never commit credentials to this repository.

## Sync and limitations

GitHub synchronizes the source code, not the lyrics stored on each device. To copy a personal lyrics library, open the app on both devices on the same Wi-Fi network and choose **歌詞庫 → 同步**. Enter the other device's local IP address and temporary pairing code. Conflicting older lyrics are kept as backups.

For cloud sync, choose **歌詞庫 → 雲端同步** or **設定 → Google 雲端備份**, connect a Google account, then press **合併並同步** on each device. The app merges local and cloud lyrics before updating its hidden Google Drive app data backup. Sync is manual. During OAuth testing, only `yuio0815@gmail.com` is authorized; Google may require signing in again after about seven days.

Local Windows and macOS builds need the corresponding Google Desktop OAuth client secrets. Put `GOOGLE_WINDOWS_CLIENT_SECRET` and `GOOGLE_MAC_CLIENT_SECRET` in an ignored `.env.google-oauth.local.json` file, then run or build with `--dart-define-from-file=.env.google-oauth.local.json`. Release builds read the same names from GitHub repository secrets. Desktop app binaries contain these client secrets, so they are not a substitute for user consent, restricted Drive scope, and PKCE.

LyricsFloat relies on metadata exposed by a player; it does not identify music from audio or transcribe songs. Online services do not have timed lyrics for every song, and their matches may need manual correction. On Windows and Android, browser sessions may represent media from sites other than YouTube. The macOS build currently reads YouTube Music tabs in Chrome or Edge, not other websites or standalone PWAs; playback access still needs a real-device permission and playback check. Android's overlay follows the app process and may need to be reopened if the system stops the app.

## Development

    flutter analyze
    flutter test
    flutter build windows --release

On a Mac, use `flutter build macos --release` instead of the Windows build command.

For Android release builds, install and configure the Android SDK first.

## Unified releases

Pushing a `v*` tag runs GitHub Actions on Windows, macOS, and Linux. After tests and all three builds succeed, the workflow attaches a Windows portable ZIP, a macOS app ZIP, and an Android arm64 APK to the same GitHub Release. To rebuild an existing tag, open **Actions → Build release packages → Run workflow**, select `main`, and enter the tag. Keep release descriptions in [RELEASE_NOTES.md](RELEASE_NOTES.md).

Android releases now require the permanent signing key in the `ANDROID_KEYSTORE_BASE64` and `ANDROID_KEYSTORE_PASSWORD` GitHub Actions secrets. Releases fail if either secret is missing or if the resulting APK has a different signing certificate. The private keystore and password are excluded from Git. See [Android signing setup](android/SIGNING.md) before the next release. APKs from releases through `v1.2.3-beta` used temporary debug keys; back up or sync lyrics, uninstall that APK, and install the first permanently signed release once. Subsequent releases can upgrade in place with the same key. The Windows ZIP is portable; the macOS app is not notarized.

## License

LyricsFloat is licensed under the [MIT License](LICENSE). The bundled OpenCC TSCharacters dictionary is third-party material licensed under Apache 2.0; see [its separate license](assets/opencc/LICENSE).
