#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shlobj.h>

#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

// CodeNote is already running: hand it the files this copy was asked to
// open (a double-clicked .codenote file). Each path goes into its own
// *.path file in %TEMP%\codenote-open, which the running app watches.
void SendFilesToRunningApp() {
  std::vector<std::string> args = GetCommandLineArguments();
  if (args.empty()) return;
  wchar_t temp[MAX_PATH + 1];
  if (::GetTempPathW(MAX_PATH + 1, temp) == 0) return;
  std::wstring inbox = std::wstring(temp) + L"codenote-open";
  ::CreateDirectoryW(inbox.c_str(), nullptr);
  int i = 0;
  for (const std::string& arg : args) {
    if (arg.empty() || arg[0] == '-') continue;
    std::wstring base = inbox + L"\\" + std::to_wstring(::GetTickCount64()) +
                        L"-" + std::to_wstring(i++);
    std::wstring partial = base + L".tmp";
    std::wstring done = base + L".path";
    HANDLE file = ::CreateFileW(partial.c_str(), GENERIC_WRITE, 0, nullptr,
                                CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) continue;
    DWORD written = 0;
    ::WriteFile(file, arg.data(), static_cast<DWORD>(arg.size()), &written,
                nullptr);
    ::CloseHandle(file);
    ::MoveFileExW(partial.c_str(), done.c_str(), MOVEFILE_REPLACE_EXISTING);
  }
}

void SetUserRegistryValue(const std::wstring& key, const std::wstring& value) {
  HKEY handle;
  if (::RegCreateKeyExW(HKEY_CURRENT_USER, key.c_str(), 0, nullptr, 0,
                        KEY_SET_VALUE, nullptr, &handle,
                        nullptr) != ERROR_SUCCESS) {
    return;
  }
  ::RegSetValueExW(handle, nullptr, 0, REG_SZ,
                   reinterpret_cast<const BYTE*>(value.c_str()),
                   static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
  ::RegCloseKey(handle);
}

// Double-clicking a .codenote file opens it in this CodeNote. Only for the
// current user (no admin rights needed), and only rewritten when CodeNote
// moved to another folder.
void RegisterCodenoteFiles() {
  wchar_t exe[MAX_PATH];
  DWORD length = ::GetModuleFileNameW(nullptr, exe, MAX_PATH);
  if (length == 0 || length == MAX_PATH) return;
  const std::wstring command = L"\"" + std::wstring(exe) + L"\" \"%1\"";
  const wchar_t* command_key =
      L"Software\\Classes\\CodeNote.File\\shell\\open\\command";
  wchar_t current[2048];
  DWORD size = sizeof(current);
  if (::RegGetValueW(HKEY_CURRENT_USER, command_key, nullptr, RRF_RT_REG_SZ,
                     nullptr, current, &size) == ERROR_SUCCESS &&
      command == current) {
    return;
  }
  SetUserRegistryValue(L"Software\\Classes\\.codenote", L"CodeNote.File");
  SetUserRegistryValue(L"Software\\Classes\\CodeNote.File", L"CodeNote file");
  SetUserRegistryValue(L"Software\\Classes\\CodeNote.File\\DefaultIcon",
                       L"\"" + std::wstring(exe) + L"\",0");
  SetUserRegistryValue(command_key, command);
  ::SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Only one CodeNote at a time (its notes storage can't be shared).
  // If it's already running, bring that window to the front and stop here.
  HANDLE single_instance =
      ::CreateMutexW(nullptr, TRUE, L"Local\\org.code.note.community");
  if (single_instance != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"CodeNote");
    if (existing != nullptr) {
      if (::IsIconic(existing)) {
        ::ShowWindow(existing, SW_RESTORE);
      }
      ::SetForegroundWindow(existing);
    }
    SendFilesToRunningApp();
    ::CloseHandle(single_instance);
    return EXIT_SUCCESS;
  }

  RegisterCodenoteFiles();

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"CodeNote", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (single_instance != nullptr) {
    ::ReleaseMutex(single_instance);
    ::CloseHandle(single_instance);
  }
  return EXIT_SUCCESS;
}
