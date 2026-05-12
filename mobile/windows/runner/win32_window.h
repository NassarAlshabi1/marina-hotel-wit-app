#ifndef WIN32_WINDOW_H_
#define WIN32_WINDOW_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <string>

class Win32Window {
 public:
  class Point {
   public:
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  class Size {
   public:
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  Win32Window();
  virtual ~Win32Window();

  bool Create(const std::wstring &title, const Point &origin, const Size &size);
  void Destroy();

  HWND GetHandle() const { return hwnd_; }

 protected:
  virtual bool OnCreate();
  virtual void OnDestroy();
  virtual LRESULT MessageHandler(HWND hwnd, UINT const message, WPARAM const wparam,
                                 LPARAM const lparam) noexcept;

 private:
  static LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wparam,
                                  LPARAM lparam) noexcept;

  HWND hwnd_ = nullptr;
};

#endif  // WIN32_WINDOW_H_
