#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr UINT kDesktopExitApprovedMessage = WM_APP + 0x47;

std::optional<int64_t> RequestId(
    const flutter::EncodableValue* arguments) {
  if (arguments == nullptr) return std::nullopt;
  const auto* map = std::get_if<flutter::EncodableMap>(arguments);
  if (map == nullptr) return std::nullopt;
  const auto entry = map->find(flutter::EncodableValue("request_id"));
  if (entry == map->end()) return std::nullopt;
  if (const auto* value = std::get_if<int64_t>(&entry->second)) return *value;
  if (const auto* value = std::get_if<int32_t>(&entry->second)) return *value;
  return std::nullopt;
}
}

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
  desktop_exit_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "com.memexlab.memex/desktop_exit",
          &flutter::StandardMethodCodec::GetInstance());
  desktop_exit_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const auto request_id = RequestId(call.arguments());
        if (!request_id.has_value() || *request_id != close_request_id_) {
          result->Error("stale_exit_request", "Request does not own close");
          return;
        }
        if (call.method_name() == "allow_close") {
          close_allowed_ = true;
          PostMessage(GetHandle(), kDesktopExitApprovedMessage, 0, 0);
          result->Success();
          return;
        }
        if (call.method_name() == "close_cancelled") {
          close_requested_ = false;
          result->Success();
          return;
        }
        result->NotImplemented();
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
  desktop_exit_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // WM_CLOSE must not reach a plugin or DefWindowProc before Dart confirms the
  // ordinary session and queue closed. An approved close intentionally bypasses
  // plugin dispatch as well, so it cannot be consumed after approval.
  if (message == WM_CLOSE) {
    if (!close_allowed_) {
      if (!close_requested_ && desktop_exit_channel_) {
        close_requested_ = true;
        ++close_request_id_;
        desktop_exit_channel_->InvokeMethod(
            "request_exit",
            std::make_unique<flutter::EncodableValue>(
                flutter::EncodableMap{{flutter::EncodableValue("request_id"),
                                       flutter::EncodableValue(
                                           close_request_id_)}}));
      }
      return 0;
    }
    return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
  }

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
    case kDesktopExitApprovedMessage:
      if (close_allowed_) {
        SendMessage(hwnd, WM_CLOSE, 0, 0);
      }
      return 0;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
