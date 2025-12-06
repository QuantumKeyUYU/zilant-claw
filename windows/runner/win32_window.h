#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>
#include <string>

class Win32Window {
 public:
  struct Point { int x; int y; };
  struct Size { int width; int height; };

  Win32Window();
  virtual ~Win32Window();

  bool CreateAndShow(const std::wstring& title, const Point& origin,
                     const Size& size);

  void Destroy();

 protected:
  virtual LRESULT MessageHandler(HWND window, UINT const message,
                                 WPARAM const wparam,
                                 LPARAM const lparam) noexcept;
  virtual void OnClosed();

  HWND GetHandle() const { return window_handle_; }

 private:
  static LRESULT CALLBACK WndProc(HWND const window, UINT const message,
                                  WPARAM const wparam, LPARAM const lparam) noexcept;

  HWND window_handle_ = nullptr;
};

#endif  // RUNNER_WIN32_WINDOW_H_
