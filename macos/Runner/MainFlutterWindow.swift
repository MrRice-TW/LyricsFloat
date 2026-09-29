import Cocoa
import FlutterMacOS

private struct PlayingTrack {
  let title: String
  let artist: String
  let album: String
  let source: String
  let positionMs: Int
  let durationMs: Int
  let isPlaying: Bool

  var channelValue: [String: Any] {
    [
      "title": title,
      "artist": artist,
      "album": album,
      "source": source,
      "positionMs": positionMs,
      "durationMs": durationMs,
      "isPlaying": isPlaying,
    ]
  }
}

private struct ScriptResult {
  let value: NSAppleEventDescriptor?
  let errorCode: Int?
}

private enum MacPlayback {
  // AppleScript calls can wait for another app. Keep them off the Flutter UI thread.
  static let queue = DispatchQueue(label: "lyrics_float.macos.playback")

  static func run(_ source: String) -> ScriptResult {
    guard let script = NSAppleScript(source: source) else {
      return ScriptResult(value: nil, errorCode: nil)
    }
    var error: NSDictionary?
    let value = script.executeAndReturnError(&error)
    return ScriptResult(
      value: value,
      errorCode: error?[NSAppleScript.errorNumber] as? Int
    )
  }

  static func spotify() -> (PlayingTrack?, Int?) {
    let script = """
      tell application id "com.spotify.client"
        if player state is stopped then return {}
        set song to current track
        return {name of song, artist of song, album of song, duration of song as string, player position as string, player state as string}
      end tell
      """
    let result = run(script)
    guard let value = result.value, value.numberOfItems == 6,
          let title = value.atIndex(1)?.stringValue, !title.isEmpty else {
      return (nil, result.errorCode)
    }
    let duration = Double(value.atIndex(4)?.stringValue ?? "") ?? 0
    let position = Double(value.atIndex(5)?.stringValue ?? "") ?? 0
    // Note: Spotify's AppleScript returns duration of track in milliseconds (e.g. 246000),
    // whereas player position is returned in seconds (e.g. 52.018).
    let durationMs = duration > 10000 ? Int(duration) : Int(duration * 1000)
    return (
      PlayingTrack(
        title: title,
        artist: value.atIndex(2)?.stringValue ?? "",
        album: value.atIndex(3)?.stringValue ?? "",
        source: "Spotify",
        positionMs: max(0, Int(position * 1000)),
        durationMs: max(0, durationMs),
        isPlaying: value.atIndex(6)?.stringValue == "playing"
      ),
      nil
    )
  }

  static func appleMusic() -> (PlayingTrack?, Int?) {
    let script = """
      tell application id "com.apple.Music"
        if player state is stopped then return {}
        set song to current track
        return {name of song, artist of song, album of song, duration of song as string, player position as string, player state as string}
      end tell
      """
    let result = run(script)
    guard let value = result.value, value.numberOfItems == 6,
          let title = value.atIndex(1)?.stringValue, !title.isEmpty else {
      return (nil, result.errorCode)
    }
    let duration = Double(value.atIndex(4)?.stringValue ?? "") ?? 0
    let position = Double(value.atIndex(5)?.stringValue ?? "") ?? 0
    let durationMs = duration > 10000 ? Int(duration) : Int(duration * 1000)
    return (
      PlayingTrack(
        title: title,
        artist: value.atIndex(2)?.stringValue ?? "",
        album: value.atIndex(3)?.stringValue ?? "",
        source: "Apple Music",
        positionMs: max(0, Int(position * 1000)),
        durationMs: max(0, durationMs),
        isPlaying: value.atIndex(6)?.stringValue == "playing"
      ),
      nil
    )
  }

  static func browser(_ bundleID: String, name: String) -> (PlayingTrack?, Int?) {
    // Read only tabs on the YouTube Music origin. Nothing is injected into other sites.
    let javascript = """
      (() => { const v = document.querySelector('video'); if (!v) return ''; const m = navigator.mediaSession && navigator.mediaSession.metadata; const bar = document.querySelector('ytmusic-player-bar'); const title = (m && m.title) || (bar && bar.querySelector('.title') && bar.querySelector('.title').textContent) || ''; const artist = (m && m.artist) || (bar && bar.querySelector('.byline a') && bar.querySelector('.byline a').textContent) || ''; if (!title.trim()) return ''; return JSON.stringify({title: title.trim(), artist: artist.trim(), album: (m && m.album) || '', positionMs: Math.round(v.currentTime * 1000), durationMs: Number.isFinite(v.duration) ? Math.round(v.duration * 1000) : 0, isPlaying: !v.paused && !v.ended}); })()
      """
    let quotedJS = "\"" + javascript
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\n", with: " ") + "\""
    let script = """
      tell application id "\(bundleID)"
        set snapshots to {}
        repeat with browserWindow in windows
          repeat with browserTab in tabs of browserWindow
            if (URL of browserTab) starts with "https://music.youtube.com/" then
              set payload to execute browserTab javascript \(quotedJS)
              if payload is not missing value and payload is not "" then set end of snapshots to payload
            end if
          end repeat
        end repeat
      end tell
      return snapshots
      """
    let result = run(script)
    guard let snapshots = result.value else { return (nil, result.errorCode) }
    var tracks: [PlayingTrack] = []
    for index in 0..<snapshots.numberOfItems {
      guard let text = snapshots.atIndex(index + 1)?.stringValue,
            let data = text.data(using: .utf8),
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let title = json["title"] as? String, !title.isEmpty else {
        continue
      }
      tracks.append(
        PlayingTrack(
          title: title,
          artist: json["artist"] as? String ?? "",
          album: json["album"] as? String ?? "",
          source: name + " · YouTube Music",
          positionMs: max(0, json["positionMs"] as? Int ?? 0),
          durationMs: max(0, json["durationMs"] as? Int ?? 0),
          isPlaying: json["isPlaying"] as? Bool ?? false
        )
      )
    }
    return (tracks.first(where: { $0.isPlaying }) ?? tracks.first, nil)
  }

  static func read(mode: String, runningBundleIDs: Set<String>) -> (PlayingTrack?, String?) {
    var tracks: [PlayingTrack] = []
    var denied = false
    var browserFailed = false
    if mode != "youtube" {
      if runningBundleIDs.contains("com.spotify.client") {
        let (track, error) = spotify()
        if let track { tracks.append(track) }
        denied = denied || error == -1743
      }
      if runningBundleIDs.contains("com.apple.Music") {
        let (track, error) = appleMusic()
        if let track { tracks.append(track) }
        denied = denied || error == -1743
      }
    }
    if mode != "spotify" {
      for (bundleID, name) in [
        ("com.google.Chrome", "Chrome"),
        ("com.microsoft.edgemac", "Edge"),
      ] where runningBundleIDs.contains(bundleID) {
        let (track, error) = browser(bundleID, name: name)
        if let track { tracks.append(track) }
        denied = denied || error == -1743
        browserFailed = browserFailed || error != nil
      }
    }
    if let playing = tracks.first(where: { $0.isPlaying }) { return (playing, nil) }
    if let first = tracks.first { return (first, nil) }
    if denied {
      return (nil, "請到 macOS「系統設定 > 隱私權與安全性 > 自動化」允許 LyricsFloat 讀取 Spotify／Apple Music／瀏覽器。")
    }
    if browserFailed {
      return (nil, "無法讀取 YouTube Music。請確認瀏覽器已允許 Apple Events 執行 JavaScript。")
    }
    return (nil, nil)
  }
}

class MainFlutterWindow: NSWindow {
  private var normalFrame: NSRect?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = frame
    contentViewController = flutterViewController
    setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let channel = FlutterMethodChannel(
      name: "lyrics_float/native",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "window", message: "視窗已關閉", details: nil))
        return
      }
      switch call.method {
      case "getStoragePath":
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        result(base.appendingPathComponent("LyricsFloat", isDirectory: true).path)
      case "getPlayback":
        let args = call.arguments as? [String: Any]
        let mode = args?["sourceMode"] as? String ?? "both"
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        MacPlayback.queue.async {
          let (track, message) = MacPlayback.read(mode: mode, runningBundleIDs: running)
          DispatchQueue.main.async {
            if let track {
              result(track.channelValue)
            } else if let message {
              result(FlutterError(code: "automation", message: message, details: nil))
            } else {
              result(nil)
            }
          }
        }
      case "setCompact":
        let enabled = (call.arguments as? [String: Any])?["enabled"] as? Bool ?? false
        if enabled {
          if normalFrame == nil { normalFrame = frame }
          level = .floating
          setContentSize(NSSize(width: 760, height: 170))
        } else {
          level = .normal
          if let normalFrame { setFrame(normalFrame, display: true, animate: true) }
          normalFrame = nil
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
