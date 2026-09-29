#include "flutter_window.h"

#include <optional>
#include <algorithm>
#include <cctype>
#include <cstdint>
#include <chrono>
#include <filesystem>
#include <string>
#include <thread>
#include <shlobj.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Media.Control.h>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

namespace {
constexpr UINT kPlaybackResultMessage = WM_APP + 17;
using MethodResult = flutter::MethodResult<flutter::EncodableValue>;

struct PlaybackResult {
  std::unique_ptr<MethodResult> result;
  std::optional<flutter::EncodableMap> value;
};

bool SourceAllowed(const std::string& source, const std::string& mode) {
  std::string lower = source;
  std::transform(lower.begin(), lower.end(), lower.begin(),
                 [](unsigned char ch) { return static_cast<char>(std::tolower(ch)); });
  const bool spotify = lower.find("spotify") != std::string::npos;
  const bool browser = lower.find("chrome") != std::string::npos ||
                       lower.find("msedge") != std::string::npos ||
                       lower.find("firefox") != std::string::npos ||
                       lower.find("brave") != std::string::npos ||
                       lower.find("opera") != std::string::npos;
  const bool youtube = lower.find("youtube") != std::string::npos || browser;
  const bool music_player = spotify ||
                            lower.find("music") != std::string::npos ||
                            lower.find("itunes") != std::string::npos ||
                            lower.find("foobar") != std::string::npos ||
                            lower.find("aimp") != std::string::npos ||
                            lower.find("cloudmusic") != std::string::npos ||
                            lower.find("qqmusic") != std::string::npos;
  if (mode == "spotify") return music_player;
  if (mode == "youtube") return youtube;
  return music_player || youtube;
}

std::optional<flutter::EncodableMap> ReadPlayback(const std::string& mode) {
  using namespace winrt::Windows::Media::Control;
  winrt::init_apartment(winrt::apartment_type::multi_threaded);
  auto manager = GlobalSystemMediaTransportControlsSessionManager::RequestAsync().get();
  auto current = manager.GetCurrentSession();
  GlobalSystemMediaTransportControlsSession session{nullptr};
  auto allowed = [&mode](const auto& item) {
    return item && SourceAllowed(Utf8FromUtf16(item.SourceAppUserModelId().c_str()), mode);
  };
  auto is_playing_session = [](const auto& item) {
    return item.GetPlaybackInfo().PlaybackStatus() ==
           GlobalSystemMediaTransportControlsSessionPlaybackStatus::Playing;
  };
  if (allowed(current) && is_playing_session(current)) session = current;
  if (!session) {
    for (const auto& item : manager.GetSessions()) {
      if (allowed(item) && is_playing_session(item)) {
        session = item;
        break;
      }
    }
  }
  if (!session && allowed(current)) session = current;
  if (!session) {
    for (const auto& item : manager.GetSessions()) {
      if (allowed(item)) {
        session = item;
        break;
      }
    }
  }
  if (!session) return std::nullopt;
  auto properties = session.TryGetMediaPropertiesAsync().get();
  auto title = Utf8FromUtf16(properties.Title().c_str());
  if (title.empty()) return std::nullopt;
  auto artist = Utf8FromUtf16(properties.Artist().c_str());
  auto album = Utf8FromUtf16(properties.AlbumTitle().c_str());
  auto source = Utf8FromUtf16(session.SourceAppUserModelId().c_str());
  auto status = session.GetPlaybackInfo().PlaybackStatus();
  bool playing = status == GlobalSystemMediaTransportControlsSessionPlaybackStatus::Playing;
  auto timeline = session.GetTimelineProperties();
  auto position = std::chrono::duration_cast<std::chrono::milliseconds>(timeline.Position()).count();
  auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(
      timeline.EndTime() - timeline.StartTime()).count();
  if (playing) {
    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
        winrt::clock::now() - timeline.LastUpdatedTime()).count();
    position += std::max<int64_t>(0, elapsed);
  }
  if (duration > 0) position = std::clamp<int64_t>(position, 0, duration);
  flutter::EncodableMap map;
  map[flutter::EncodableValue("title")] = flutter::EncodableValue(title);
  map[flutter::EncodableValue("artist")] = flutter::EncodableValue(artist);
  map[flutter::EncodableValue("album")] = flutter::EncodableValue(album);
  map[flutter::EncodableValue("source")] = flutter::EncodableValue(source);
  map[flutter::EncodableValue("positionMs")] = flutter::EncodableValue(static_cast<int64_t>(std::max<int64_t>(0, position)));
  map[flutter::EncodableValue("durationMs")] = flutter::EncodableValue(static_cast<int64_t>(std::max<int64_t>(0, duration)));
  map[flutter::EncodableValue("isPlaying")] = flutter::EncodableValue(playing);
  return map;
}
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  native_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "lyrics_float/native",
      &flutter::StandardMethodCodec::GetInstance());
  native_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<MethodResult> result) {
        if (call.method_name() == "getStoragePath") {
          PWSTR path = nullptr;
          if (SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &path) != S_OK) {
            result->Error("storage", "Cannot find LocalAppData");
            return;
          }
          auto value = Utf8FromUtf16(path) + "\\LyricsFloat";
          CoTaskMemFree(path);
          result->Success(flutter::EncodableValue(value));
        } else if (call.method_name() == "getPlayback") {
          std::string mode = "both";
          if (call.arguments()) {
            const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
            if (args) {
              auto it = args->find(flutter::EncodableValue("sourceMode"));
              if (it != args->end()) {
                if (const auto* value = std::get_if<std::string>(&it->second)) mode = *value;
              }
            }
          }
          auto pending = new PlaybackResult{std::move(result), std::nullopt};
          HWND window = GetHandle();
          std::thread([pending, window, mode]() {
            try { pending->value = ReadPlayback(mode); } catch (...) {}
            if (!PostMessage(window, kPlaybackResultMessage, 0,
                             reinterpret_cast<LPARAM>(pending))) {
              delete pending;
            }
          }).detach();
        } else if (call.method_name() == "setCompact") {
          bool enabled = false;
          if (call.arguments()) {
            const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
            if (args) {
              auto it = args->find(flutter::EncodableValue("enabled"));
              if (it != args->end()) {
                if (const auto* flag = std::get_if<bool>(&it->second)) enabled = *flag;
              }
            }
          }
          SetWindowPos(GetHandle(), enabled ? HWND_TOPMOST : HWND_NOTOPMOST,
                       0, 0, enabled ? 760 : 1100, enabled ? 200 : 700,
                       SWP_NOMOVE | SWP_SHOWWINDOW);
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  native_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case kPlaybackResultMessage: {
      std::unique_ptr<PlaybackResult> pending(
          reinterpret_cast<PlaybackResult*>(lparam));
      if (pending->value) {
        pending->result->Success(flutter::EncodableValue(*pending->value));
      } else {
        pending->result->Success();
      }
      return 0;
    }
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
