#include <AbilityKit/native_child_process.h>
#include <hilog/log.h>
#include <sys/stat.h>
#include <unistd.h>

#include <cstdio>
#include <string>

extern "C" void startServerProcess(const char *socketPathChar, const char *logPathChar);

namespace {

constexpr unsigned int kLogDomain = 0xFF12;
constexpr char kChildLogTag[] = "FlClashChild";

std::string DirName(const std::string &path) {
  const auto index = path.find_last_of('/');
  if (index == std::string::npos) {
    return ".";
  }
  if (index == 0) {
    return "/";
  }
  return path.substr(0, index);
}

std::string JoinPath(const std::string &left, const std::string &right) {
  if (left.empty() || left == ".") {
    return right;
  }
  if (left.back() == '/') {
    return left + right;
  }
  return left + "/" + right;
}

void LogChild(const std::string &message) {
  OH_LOG_PrintMsg(LOG_APP, LOG_INFO, kLogDomain, kChildLogTag, message.c_str());
  std::fprintf(stderr, "[OHOS-CHILD] %s\n", message.c_str());
  std::fflush(stderr);
}

void AppendDebugLog(const std::string &path, const std::string &message) {
  if (path.empty()) {
    return;
  }
  FILE *file = std::fopen(path.c_str(), "a");
  if (file == nullptr) {
    return;
  }
  std::fprintf(file, "%s\n", message.c_str());
  std::fclose(file);
}

std::string BuildChildDebugLogPath(const std::string &entry_params) {
  if (entry_params.empty()) {
    return {};
  }
  const auto temp_dir = DirName(entry_params);
  const auto base_dir = DirName(temp_dir);
  return JoinPath(JoinPath(base_dir, "files"), "flclash-child.log");
}

std::string BuildChildCoreLogPath(const std::string &entry_params) {
  if (entry_params.empty()) {
    return {};
  }
  const auto temp_dir = DirName(entry_params);
  const auto base_dir = DirName(temp_dir);
  return JoinPath(JoinPath(base_dir, "files"), "flclash-core.log");
}

}  // namespace

extern "C" __attribute__((constructor)) void TraceEntryChildLibraryLoad(void) {
  LogChild("libentry_child loaded pid=" + std::to_string(getpid()));
}

extern "C" __attribute__((visibility("default"))) void FlClashCoreMain(
    NativeChildProcess_Args args) {
  const std::string entry_params =
      args.entryParams == nullptr ? std::string() : std::string(args.entryParams);
  const std::string debug_log_path = BuildChildDebugLogPath(entry_params);
  const std::string core_log_path = BuildChildCoreLogPath(entry_params);

  AppendDebugLog(debug_log_path, "FlClashCoreMain entry socket=" + entry_params);
  LogChild("FlClashCoreMain entry socket=" + entry_params);

  startServerProcess(
      entry_params.empty() ? nullptr : entry_params.c_str(),
      core_log_path.empty() ? nullptr : core_log_path.c_str());

  AppendDebugLog(debug_log_path, "startServerProcess returned");
  LogChild("startServerProcess returned");
}
