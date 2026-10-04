import Flutter
import UIKit
import SpotifyiOS

@main
@objc class AppDelegate: FlutterAppDelegate, SPTAppRemoteDelegate, SPTAppRemotePlayerStateDelegate {
  private var remote: SPTAppRemote?
  private var playback: [String: Any]?
  private var sampledAt = Date()
  private var remoteError: String?
  private let redirectURL = URL(string: "lyricsfloat-spotify://callback")!
  private var native: FlutterMethodChannel?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "lyrics_float/native", binaryMessenger: controller.binaryMessenger)
      native = channel
      channel.setMethodCallHandler { [weak self] call, result in
        self?.handle(call, result: result)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getStoragePath":
      do {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent("LyricsFloat", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        result(directory.path)
      } catch { result(FlutterError(code: "storage", message: "Could not open local storage", details: nil)) }
    case "configureSpotify":
      let args = call.arguments as? [String: Any]
      if let clientID = args?["clientId"] as? String, !clientID.isEmpty {
        let configuration = SPTConfiguration(clientID: clientID, redirectURL: redirectURL)
        let appRemote = SPTAppRemote(configuration: configuration, logLevel: .none)
        appRemote.delegate = self
        remote = appRemote
      }
      result(remote != nil)
    case "connectSpotify":
      guard let remote = remote else {
        result(FlutterError(code: "spotify_config", message: "Spotify Client ID is not configured", details: nil))
        return
      }
      guard UIApplication.shared.canOpenURL(URL(string: "spotify:")!) else {
        result(FlutterError(code: "spotify_missing", message: "Install Spotify and sign in first", details: nil))
        return
      }
      remoteError = nil
      if remote.connectionParameters.accessToken != nil {
        remote.connect()
      } else {
        // Spotify's empty URI resumes the user's track after authorization.
        remote.authorizeAndPlayURI("", completionHandler: nil)
      }
      result(true)
    case "disconnectSpotify":
      remote?.disconnect()
      remote?.connectionParameters.accessToken = nil
      playback = nil
      remoteError = nil
      result(nil)
    case "hasMediaAccess": result(remote?.isConnected ?? false)
    case "getPlayback":
      if let error = remoteError {
        result(FlutterError(code: "spotify_connection", message: error, details: nil))
      } else if remote?.isConnected == true, var snapshot = playback {
        let position = snapshot["positionMs"] as? Int ?? 0
        let duration = snapshot["durationMs"] as? Int ?? 0
        let elapsed = snapshot["isPlaying"] as? Bool == true ? max(0, Int(Date().timeIntervalSince(sampledAt) * 1000)) : 0
        snapshot["positionMs"] = duration > 0 ? min(duration, position + elapsed) : position + elapsed
        result(snapshot)
      } else { result(nil) }
    default: result(FlutterMethodNotImplemented)
    }
  }

  override func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    guard url.scheme == redirectURL.scheme, url.host == redirectURL.host, let remote = remote else {
      return super.application(app, open: url, options: options)
    }
    let parameters = remote.authorizationParameters(from: url)
    if let token = parameters?[SPTAppRemoteAccessTokenKey] {
      remote.connectionParameters.accessToken = token
      remote.connect()
    } else {
      // Never include a callback URL or access token in UI errors.
      remoteError = "Spotify authorization was not completed. Please connect again."
    }
    return true
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    if let remote = remote, remote.connectionParameters.accessToken != nil, !remote.isConnected {
      remote.connect()
    }
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    remote?.disconnect()
    playback = nil
    super.applicationWillResignActive(application)
  }

  func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
    remoteError = nil
    appRemote.playerAPI?.delegate = self
    appRemote.playerAPI?.subscribe(toPlayerState: { [weak self] _, error in
      if error != nil { self?.remoteError = "Could not read Spotify playback. Please reconnect." }
    })
    appRemote.playerAPI?.getPlayerState({ [weak self] result, _ in
      if let state = result as? SPTAppRemotePlayerState { self?.playerStateDidChange(state) }
    })
  }

  func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) { playback = nil }
  func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
    playback = nil
    remoteError = "Could not connect to Spotify. Open Spotify and try connecting again."
  }

  func playerStateDidChange(_ state: SPTAppRemotePlayerState) {
    sampledAt = Date()
    playback = [
      "title": state.track.name, "artist": state.track.artist.name,
      "album": state.track.album.name, "source": "Spotify",
      "positionMs": Int(state.playbackPosition), "durationMs": Int(state.track.duration),
      "isPlaying": !state.isPaused,
    ]
  }
}
