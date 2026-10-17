#include "proxy_cleanup.h"

#include <windows.h>
#include <wininet.h>

#include <cwctype>
#include <string>

namespace {

constexpr wchar_t kInternetSettingsKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings";

// 当前系统代理是否指向本机（即很可能由我们设置）。
// 旧实现无条件清零 ProxyEnable 并删除 ProxyServer / ProxyOverride：用户同时
// 使用别的代理工具或手工配置时，关机/注销会把它们悄悄清掉，且无从归因。
bool PointsToLocalhost(const std::wstring& server) {
  std::wstring lower = server;
  for (auto& c : lower) {
    c = static_cast<wchar_t>(::towlower(c));
  }
  return lower.find(L"127.0.0.1:") != std::wstring::npos ||
         lower.find(L"localhost:") != std::wstring::npos ||
         lower.find(L"[::1]:") != std::wstring::npos;
}

bool SystemProxyOwnedByUs(HKEY key) {
  wchar_t buffer[1024] = {};
  DWORD size = sizeof(buffer);
  DWORD type = 0;
  if (::RegQueryValueExW(key, L"ProxyServer", nullptr, &type,
                         reinterpret_cast<LPBYTE>(buffer),
                         &size) != ERROR_SUCCESS) {
    return false;
  }
  if (type != REG_SZ && type != REG_EXPAND_SZ) {
    return false;
  }
  std::wstring server(buffer, size / sizeof(wchar_t));
  while (!server.empty() && server.back() == L'\0') {
    server.pop_back();
  }
  return PointsToLocalhost(server);
}

}  // namespace

void ClearSystemProxy() {
  HKEY internet_settings = nullptr;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER, kInternetSettingsKey, 0,
                      KEY_QUERY_VALUE | KEY_SET_VALUE,
                      &internet_settings) != ERROR_SUCCESS) {
    return;
  }

  if (!SystemProxyOwnedByUs(internet_settings)) {
    ::RegCloseKey(internet_settings);
    return;
  }

  DWORD disabled = 0;
  ::RegSetValueExW(internet_settings, L"ProxyEnable", 0, REG_DWORD,
                   reinterpret_cast<const BYTE*>(&disabled), sizeof(disabled));
  ::RegDeleteValueW(internet_settings, L"ProxyServer");
  ::RegDeleteValueW(internet_settings, L"ProxyOverride");
  ::RegCloseKey(internet_settings);

  ::InternetSetOptionW(nullptr, INTERNET_OPTION_SETTINGS_CHANGED, nullptr, 0);
  ::InternetSetOptionW(nullptr, INTERNET_OPTION_REFRESH, nullptr, 0);
}

