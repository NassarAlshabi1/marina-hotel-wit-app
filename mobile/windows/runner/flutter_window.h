#ifndef FLUTTER_WINDOW_H_
#define FLUTTER_WINDOW_H_

#include <flutter/dart_api.h>
#include <flutter/flutter_windows.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

class FlutterWindow : public Win32Window {
 public:
  explicit FlutterWindow(const flutter::DartProject &project);
  ~FlutterWindow() override;

 protected:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND hwnd, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  flutter::DartProject project_;
  std::unique_ptr<flutter::FlutterWindowsViewController> flutter_controller_;
};

#endif  // FLUTTER_WINDOW_H_
