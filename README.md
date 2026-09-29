# LyricsFloat

[English](README.md) | [繁體中文](README.zh-TW.md)

LyricsFloat is an early-stage Flutter app for Windows, macOS, and Android that displays synchronized lyrics for music playing in other apps. Windows and Android read system media sessions; macOS uses user-approved automation to read Spotify or YouTube Music browser tabs. No Spotify account linking or Premium subscription is needed.

## Features

- Displays the current, previous, and next lyric lines in the main window. Android offers a movable two-line overlay; Windows and macOS offer compact always-on-top lyrics windows.
- Reads song title, artist, playback state, and position from Windows Media Control, Android media sessions, the macOS Spotify app, or YouTube Music tabs in Chrome or Edge on macOS.
- Lets users select Spotify, YouTube/browser media, or both as playback sources. Windows and Android cannot limit browser media to a particular website because the system does not provide the tab URL; macOS reads only `music.youtube.com` tabs.
- Searches LRCLIB, AMLL, and LrcAPI for matching timed LRC lyrics. Musixmatch and Tencent Yinsuda are optional sources that require users' own credentials and may have provider costs.
- Offers manual search with multiple candidate sources, a live preview before saving, a quick editor for the current song, and a persistent timing adjustment for each song.
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

    flutter run -d macos

Build a local macOS release app:

    flutter build macos --release

The app is created at `build/macos/Build/Products/Release/lyrics_float.app`. On first use, allow LyricsFloat to automate Spotify or your browser. If you previously denied access, update it in **System Settings → Privacy & Security → Automation**. For YouTube Music, turn on **View → Developer → Allow JavaScript from Apple Events** in Chrome or Edge and keep a `music.youtube.com` tab open. The compact lyrics window can be moved by its title bar. Local builds do not require a paid Apple account; distribution to other Macs requires Apple signing and notarization.

On Android, grant notification access so the app can read active media sessions. The floating lyrics overlay also requires permission to display over other apps. On Windows, allow private-network firewall access if you plan to sync lyrics over Wi-Fi.

## Use lyrics

When a supported player exposes a song title and artist, LyricsFloat checks the local library first, then searches the enabled online lyric sources. It accepts matching timed lyrics and avoids automatically choosing between ambiguous versions. Simplified and Traditional Chinese titles can be treated as equivalent, and a trailing “- Topic” artist label is ignored during matching.

If the automatic search misses a song, use **Search by song name** to edit the suggested title and artist. Choose a result to preview it against the current playback position, then save it only if the lyrics and timing match. You can also import an LRC file or paste timed lines such as:

    [00:12.50]First lyric line
    [00:16.20]Second lyric line

Use **Edit current lyrics** to open the song being displayed without searching the library. The timing controls move lyrics in 0.5-second steps and save the adjustment for that song.

The settings menu controls both playback sources and online lyric sources. The three free lookup sources are enabled by default. Disabling every online lyric source stops automatic lookup without deleting saved lyrics.

## Optional lyric providers

Musixmatch requires a developer key with access to synchronized lyrics. Set the MUSIXMATCH_API_KEY environment variable before launching the app, then enable Musixmatch under lyric sources.

Tencent Yinsuda requires an approved use case and provider credentials. Set TENCENT_SECRET_ID, TENCENT_SECRET_KEY, TENCENT_YINSUDA_APP_NAME, and TENCENT_YINSUDA_USER_ID before launching the app, then enable Tencent Yinsuda. Confirm that your provider agreement permits lyric display, local storage, and sharing before use. Both optional providers are disabled by default. Never commit credentials to this repository.

## Sync and limitations

GitHub synchronizes the source code, not the lyrics stored on each device. To copy a personal lyrics library, open the app on both devices on the same Wi-Fi network and use **Sync lyrics** with the other device's local IP address and temporary pairing code. Conflicting older lyrics are kept as backups.

LyricsFloat relies on metadata exposed by a player; it does not identify music from audio or transcribe songs. Online services do not have timed lyrics for every song, and their matches may need manual correction. On Windows and Android, browser sessions may represent media from sites other than YouTube. The macOS build currently reads YouTube Music tabs in Chrome or Edge, not other websites or standalone PWAs; playback access still needs a real-device permission and playback check. Android's overlay follows the app process and may need to be reopened if the system stops the app. Google Drive sync is not implemented.

## Development

    flutter analyze
    flutter test
    flutter build windows --release

On a Mac, use `flutter build macos --release` instead of the Windows build command.

For Android release builds, install and configure the Android SDK first.

## Unified releases

Pushing a `v*` tag runs GitHub Actions on Windows, macOS, and Linux. After tests and all three builds succeed, the workflow attaches a Windows portable ZIP, a macOS app ZIP, and an Android arm64 APK to the same GitHub Release. To rebuild an existing tag, open **Actions → Build release packages → Run workflow**, select `main`, and enter the tag. Keep release descriptions in [RELEASE_NOTES.md](RELEASE_NOTES.md).

The Android APK currently uses a debug signing key generated by the build machine. Its signature may differ from an earlier APK, so back up lyrics with the in-app Wi-Fi sync before replacing an installation. A fixed release signing key is needed for seamless Android upgrades. The Windows ZIP is portable; the macOS app is not notarized.

## License

LyricsFloat is licensed under the [MIT License](LICENSE). The bundled OpenCC TSCharacters dictionary is third-party material licensed under Apache 2.0; see [its separate license](assets/opencc/LICENSE).
