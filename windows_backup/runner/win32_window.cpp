#include "win32_window.h"

#include <dwmapi.h>
#include <windowsx.h>

Win32Window::Win32Window() {}
Win32Window::~Win32Window() { Destroy(); }

bool Win32Window::CreateAndShow(const std::wstring& title, const Point& origin,
                                const Size& size) {
  WNDCLASS window_class = {};
  window_class.lpfnWndProc = Win32Window::WndProc;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpszClassName = L"FlutterWindowClass";
  RegisterClass(&window_class);

  RECT frame = {origin.x, origin.y, origin.x + size.width, origin.y + size.height};
  AdjustWindowRect(&frame, WS_OVERLAPPEDWINDOW, FALSE);

  window_handle_ = CreateWindow(
      window_class.lpszClassName, title.c_str(), WS_OVERLAPPEDWINDOW | WS_VISIBLE,
      frame.left, frame.top, frame.right - frame.left, frame.bottom - frame.top,
      nullptr, nullptr, window_class.hInstance, this);

  return window_handle_ != nullptr;
}

void Win32Window::Destroy() {
  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
}

LRESULT CALLBACK Win32Window::WndProc(HWND const window, UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto create_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    auto that = static_cast<Win32Window*>(create_struct->lpCreateParams);
    SetWindowLongPtr(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(that));
    return DefWindowProc(window, message, wparam, lparam);
  }

  auto that = reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
  if (that) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT Win32Window::MessageHandler(HWND window, UINT const message,
                                    WPARAM const wparam,
                                    LPARAM const lparam) noexcept {
  switch (message) {
    case WM_DESTROY:
      window_handle_ = nullptr;
      OnClosed();
      return 0;
    default:
      return DefWindowProc(window, message, wparam, lparam);
  }
}

void Win32Window::OnClosed() {}
