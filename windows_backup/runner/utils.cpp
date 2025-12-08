#include "utils.h"

#include <windows.h>

std::wstring Utf8ToWide(const std::string& utf8_string) {
  if (utf8_string.empty()) {
    return std::wstring();
  }
  int wide_length = MultiByteToWideChar(CP_UTF8, 0, utf8_string.c_str(),
                                        static_cast<int>(utf8_string.length()),
                                        nullptr, 0);
  std::wstring wide_string(wide_length, 0);
  MultiByteToWideChar(CP_UTF8, 0, utf8_string.c_str(),
                      static_cast<int>(utf8_string.length()),
                      wide_string.data(), wide_length);
  return wide_string;
}
