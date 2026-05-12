#include "win32_window.h"

#include <windows.h>

#include <flutter_windows.h>

#include <string>

#include "utils.h"

Win32Window::Win32Window() = default;
Win32Window::~Win32Window() = default;

bool Win32Window::Create(const std::wstring &title, const Point &origin,
                         const Size &size) {
  WNDCLASS wc{};
  wc.hInstance = GetModuleHandle(nullptr);
  wc.lpszClassName = L"FLUTTER_RUNNER_WIN32_WINDOW";
  wc.lpfnWndProc = WndProc;
  RegisterClass(&wc);

  hwnd_ = CreateWindow(
      wc.lpszClassName, title.c_str(), WS_OVERLAPPEDWINDOW,
      static_cast<int>(origin.x), static_cast<int>(origin.y),
      static_cast<int>(size.width), static_cast<int>(size.height),
      nullptr, nullptr, wc.hInstance, this);

  return hwnd_ != nullptr;
}

void Win32Window::Destroy() {
  if (hwnd_) {
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
}

bool Win32Window::OnCreate() { return true; }
void Win32Window::OnDestroy() {}

LRESULT Win32Window::MessageHandler(HWND hwnd, UINT const message,
                                    WPARAM const wparam,
                                    LPARAM const lparam) noexcept {
  return DefWindowProc(hwnd, message, wparam, lparam);
}

LRESULT CALLBACK Win32Window::WndProc(HWND hwnd, UINT message, WPARAM wparam,
                                      LPARAM lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto cs = reinterpret_cast<CREATESTRUCT *>(lparam);
    SetWindowLongPtr(hwnd, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(cs->lpCreateParams));
  }

  auto window = reinterpret_cast<Win32Window *>(
      GetWindowLongPtr(hwnd, GWLP_USERDATA));

  if (window) {
    return window->MessageHandler(hwnd, message, wparam, lparam);
  }

  return DefWindowProc(hwnd, message, wparam, lparam);
}
