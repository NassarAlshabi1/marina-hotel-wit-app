#ifndef RUNNER_UTILS_H_
#define RUNNER_UTILS_H_

#include <string>
#include <vector>

std::string Utf8FromUtf16(const std::wstring &utf16_string);
std::wstring Utf16FromUtf8(const std::string &utf8_string);

#endif  // RUNNER_UTILS_H_
