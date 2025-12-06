#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "win32_window.h"

int APIENTRY wWinMain(HINSTANCE instance, HINSTANCE, wchar_t*, int show_command) {
  flutter::DartProject project(L"data");

  FlutterWindow window(project);
  Win32Window::Point origin{10, 10};
  Win32Window::Size size{1280, 720};
  if (!window.CreateAndShow(L"Digital Defender", origin, size)) {
    return EXIT_FAILURE;
  }

  ShowWindow(window.GetHandle(), show_command);
  UpdateWindow(window.GetHandle());

  MSG message;
  while (GetMessage(&message, nullptr, 0, 0)) {
    TranslateMessage(&message);
    DispatchMessage(&message);
  }

  return 0;
}
