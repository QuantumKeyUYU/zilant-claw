#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <iostream>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

void FlutterWindow::OnClosed() { Win32Window::Destroy(); }

LRESULT FlutterWindow::MessageHandler(HWND window, UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    return DefWindowProc(window, message, wparam, lparam);
  }

  switch (message) {
    case WM_CREATE: {
      flutter::FlutterViewController::ViewProperties view_properties = {};
      view_properties.width = 1024;
      view_properties.height = 640;

      flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
          view_properties, project_);
      RegisterPlugins(flutter_controller_->engine());

      auto messenger = flutter_controller_->engine()->binary_messenger();
      method_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "digital_defender/protection",
          &flutter::StandardMethodCodec::GetInstance());

      method_channel_->SetMethodCallHandler([
        ](const auto& call,
           std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "windows_start_protection") {
          OutputDebugString(L"Windows protection ON (stub)\n");
          std::cout << "Windows protection ON (stub)" << std::endl;
          result->Success();
        } else if (call.method_name() == "windows_stop_protection") {
          OutputDebugString(L"Windows protection OFF (stub)\n");
          std::cout << "Windows protection OFF (stub)" << std::endl;
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

      SetWindowLongPtr(window, GWLP_USERDATA,
                       reinterpret_cast<LONG_PTR>(flutter_controller_.get()));
      return 0;
    }
    case WM_DESTROY:
      flutter_controller_.reset();
      method_channel_.reset();
      break;
  }

  if (flutter_controller_) {
    return flutter_controller_->HandleTopLevelWindowProc(window, message, wparam,
                                                        lparam);
  }

  return Win32Window::MessageHandler(window, message, wparam, lparam);
}
