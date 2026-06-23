#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <condition_variable>
#include <cctype>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include <AbilityKit/native_child_process.h>
#include <hilog/log.h>
#include "napi/native_api.h"

namespace {

using InvokeActionFn = void (*)(void *, const char *);
using FreeCStringFn = void (*)(char *);
using SetEventListenerFn = void (*)(void *);
using StartTunFn = bool (*)(void *, int, char *, char *, char *);
using StopTunFn = void (*)();

constexpr auto kInvokeTimeout = std::chrono::seconds(15);
constexpr char kEntryLibraryDebugLogPath[] =
    "/data/storage/el2/base/files/flclash-libentry.log";
constexpr unsigned int kLogDomain = 0xFF12;
constexpr char kEntryLogTag[] = "FlClashEntry";
constexpr char kCoreLogTag[] = "FlClashCore";

std::string g_last_error;
void *g_core_handle = nullptr;
InvokeActionFn g_invoke_action = nullptr;
FreeCStringFn g_free_c_string = nullptr;
SetEventListenerFn g_set_event_listener = nullptr;
StartTunFn g_start_tun = nullptr;
StopTunFn g_stop_tun = nullptr;
bool g_event_listener_registered = false;
std::mutex g_state_mutex;
std::vector<std::string> g_event_payloads;

struct PendingResult {
  std::mutex mutex;
  std::condition_variable condition;
  bool completed = false;
  std::string payload;
};

void ResultCallback(const char *data);

std::unordered_map<std::string, std::shared_ptr<PendingResult>> g_pending_results;
std::unordered_set<std::string> g_detached_ids;
std::mutex g_probe_mutex;
std::condition_variable g_probe_condition;
bool g_probe_completed = false;
int g_probe_result = NCP_ERR_TIMEOUT;
std::mutex g_exit_mutex;
std::condition_variable g_exit_condition;
bool g_exit_received = false;
int32_t g_exit_pid = -1;
int32_t g_exit_signal = 0;

void ClearError() {
  g_last_error.clear();
}

bool SetError(const std::string &message) {
  g_last_error = message;
  return false;
}

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

void LogChildProcess(const std::string &message) {
  OH_LOG_PrintMsg(LOG_APP, LOG_INFO, kLogDomain, kCoreLogTag, message.c_str());
  std::fprintf(stderr, "[OHOS-CORE] %s\n", message.c_str());
  std::fflush(stderr);
}

void LogEntryProcess(const std::string &message) {
  OH_LOG_PrintMsg(LOG_APP, LOG_INFO, kLogDomain, kEntryLogTag, message.c_str());
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

void AppendEarlyDebugLog(const std::string &message) {
  LogEntryProcess(message);
  AppendDebugLog(kEntryLibraryDebugLogPath, message);
  std::fprintf(stderr, "[OHOS-ENTRY] %s\n", message.c_str());
  std::fflush(stderr);
}

std::vector<std::string> BuildCoreCandidates(const char *entry_library_path) {
  const std::string library_path = entry_library_path == nullptr
                                       ? std::string()
                                       : std::string(entry_library_path);
  const std::string library_dir = DirName(library_path);
  const std::string libs_dir = DirName(library_dir);
  return {
      JoinPath(library_dir, "FlClashCore"),
      JoinPath(library_dir, "libFlClashCore.so"),
      JoinPath(JoinPath(libs_dir, "arm64-v8a"), "FlClashCore"),
      JoinPath(JoinPath(libs_dir, "arm64-v8a"), "libFlClashCore.so"),
      JoinPath(JoinPath(libs_dir, "arm64"), "FlClashCore"),
      JoinPath(JoinPath(libs_dir, "arm64"), "libFlClashCore.so"),
  };
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

bool EnsureCoreLoaded() {
  if (g_invoke_action != nullptr && g_start_tun != nullptr &&
      g_stop_tun != nullptr) {
    return true;
  }
  std::lock_guard<std::mutex> lock(g_state_mutex);
  if (g_invoke_action != nullptr && g_start_tun != nullptr &&
      g_stop_tun != nullptr) {
    return true;
  }
  ClearError();
  dlerror();
  g_core_handle = dlopen("libclash.so", RTLD_NOW | RTLD_LOCAL);
  if (g_core_handle == nullptr) {
    const char *error = dlerror();
    return SetError(error == nullptr ? "dlopen libclash.so failed" : error);
  }
  auto symbol = dlsym(g_core_handle, "invokeAction");
  if (symbol == nullptr) {
    const char *error = dlerror();
    return SetError(error == nullptr ? "dlsym invokeAction failed" : error);
  }
  g_invoke_action = reinterpret_cast<InvokeActionFn>(symbol);
  auto free_symbol = dlsym(g_core_handle, "freeCString");
  if (free_symbol == nullptr) {
    const char *error = dlerror();
    g_invoke_action = nullptr;
    return SetError(error == nullptr ? "dlsym freeCString failed" : error);
  }
  g_free_c_string = reinterpret_cast<FreeCStringFn>(free_symbol);
  auto event_listener_symbol = dlsym(g_core_handle, "setEventListener");
  if (event_listener_symbol != nullptr) {
    g_set_event_listener =
        reinterpret_cast<SetEventListenerFn>(event_listener_symbol);
  }
  auto start_tun_symbol = dlsym(g_core_handle, "startTUN");
  if (start_tun_symbol == nullptr) {
    const char *error = dlerror();
    g_invoke_action = nullptr;
    g_free_c_string = nullptr;
    g_set_event_listener = nullptr;
    return SetError(error == nullptr ? "dlsym startTUN failed" : error);
  }
  g_start_tun = reinterpret_cast<StartTunFn>(start_tun_symbol);
  auto stop_tun_symbol = dlsym(g_core_handle, "stopTun");
  if (stop_tun_symbol == nullptr) {
    const char *error = dlerror();
    g_invoke_action = nullptr;
    g_free_c_string = nullptr;
    g_set_event_listener = nullptr;
    g_start_tun = nullptr;
    return SetError(error == nullptr ? "dlsym stopTun failed" : error);
  }
  g_stop_tun = reinterpret_cast<StopTunFn>(stop_tun_symbol);
  if (g_set_event_listener != nullptr && !g_event_listener_registered) {
    g_set_event_listener(reinterpret_cast<void *>(&ResultCallback));
    g_event_listener_registered = true;
  }
  return true;
}

std::string ConsumeQueuedCoreEvents() {
  std::lock_guard<std::mutex> lock(g_state_mutex);
  if (g_event_payloads.empty()) {
    return "[]";
  }
  AppendEarlyDebugLog(
      "consumeCoreEvents count=" + std::to_string(g_event_payloads.size()));
  std::string result = "[";
  for (size_t index = 0; index < g_event_payloads.size(); ++index) {
    if (index > 0) {
      result += ",";
    }
    result += g_event_payloads[index];
  }
  result += "]";
  g_event_payloads.clear();
  return result;
}

size_t SkipWhitespace(const std::string &value, size_t index) {
  while (index < value.size() &&
         std::isspace(static_cast<unsigned char>(value[index])) != 0) {
    ++index;
  }
  return index;
}

std::string ExtractJsonStringField(
    const std::string &payload,
    const char *field_name) {
  const std::string key = std::string("\"") + field_name + "\"";
  auto key_index = payload.find(key);
  if (key_index == std::string::npos) {
    return "";
  }
  auto colon_index = payload.find(':', key_index + key.size());
  if (colon_index == std::string::npos) {
    return "";
  }
  auto value_index = SkipWhitespace(payload, colon_index + 1);
  if (value_index >= payload.size() || payload[value_index] != '"') {
    return "";
  }
  ++value_index;
  std::string result;
  while (value_index < payload.size()) {
    const auto current = payload[value_index];
    if (current == '\\') {
      if (value_index + 1 >= payload.size()) {
        return "";
      }
      result.push_back(payload[value_index + 1]);
      value_index += 2;
      continue;
    }
    if (current == '"') {
      return result;
    }
    result.push_back(current);
    ++value_index;
  }
  return "";
}

bool IsDetachedActionMethod(const std::string &method) {
  return method == "updateGeoData" || method == "updateExternalProvider";
}

std::string BuildImmediateSuccessResult(
    const std::string &method,
    const std::string &id) {
  return std::string("{\"method\":\"") + method +
         "\",\"data\":\"\",\"id\":\"" + id +
         "\",\"code\":0}";
}

void ResultCallback(const char *data) {
  std::string payload;
  if (data != nullptr) {
    payload = data;
    if (g_free_c_string != nullptr) {
      g_free_c_string(const_cast<char *>(data));
    }
  }
  std::shared_ptr<PendingResult> pending_result;
  const auto id = ExtractJsonStringField(payload, "id");
  const auto method = ExtractJsonStringField(payload, "method");
  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    if (data == nullptr) {
      g_last_error = "native callback returned null";
      AppendEarlyDebugLog("ResultCallback received null data");
      return;
    }
    if (id.empty()) {
      AppendEarlyDebugLog(
          "ResultCallback queue core event method=" + method +
          " payload=" + payload);
      g_event_payloads.push_back(payload);
      return;
    }
    AppendEarlyDebugLog(
        "ResultCallback method=" + method + " id=" + id +
        " payload=" + payload);
    auto detached_it = g_detached_ids.find(id);
    if (detached_it != g_detached_ids.end()) {
      g_detached_ids.erase(detached_it);
      const auto result = ExtractJsonStringField(payload, "data");
      if (!result.empty()) {
        AppendEarlyDebugLog(
            "detached invokeCore callback method=" + method + " id=" + id +
            " error=" + result);
      } else {
        AppendEarlyDebugLog(
            "detached invokeCore callback method=" + method + " id=" + id +
            " done");
      }
      return;
    }
    auto pending_it = g_pending_results.find(id);
    if (pending_it == g_pending_results.end()) {
      g_last_error = "unexpected core callback id: " + id;
      AppendEarlyDebugLog("ResultCallback unexpected id=" + id +
                          " method=" + method);
      return;
    }
    pending_result = pending_it->second;
  }
  {
    std::lock_guard<std::mutex> lock(pending_result->mutex);
    pending_result->payload = payload;
    pending_result->completed = true;
  }
  pending_result->condition.notify_one();
}

napi_value CreateString(napi_env env, const std::string &value) {
  napi_value result = nullptr;
  napi_create_string_utf8(env, value.c_str(), value.size(), &result);
  return result;
}

napi_value CreateBool(napi_env env, bool value) {
  napi_value result = nullptr;
  napi_get_boolean(env, value, &result);
  return result;
}

napi_value CreateInt32(napi_env env, int32_t value) {
  napi_value result = nullptr;
  napi_create_int32(env, value, &result);
  return result;
}

std::string InvokeCoreBlocking(const std::string &action) {
  if (!EnsureCoreLoaded()) {
    return "";
  }

  const auto id = ExtractJsonStringField(action, "id");
  if (id.empty()) {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    SetError("missing action id in invokeCore payload");
    return "";
  }
  const auto method = ExtractJsonStringField(action, "method");
  if (IsDetachedActionMethod(method)) {
    {
      std::lock_guard<std::mutex> lock(g_state_mutex);
      ClearError();
      g_detached_ids.insert(id);
    }
    g_invoke_action(reinterpret_cast<void *>(&ResultCallback), action.c_str());
    return BuildImmediateSuccessResult(method, id);
  }

  auto pending_result = std::make_shared<PendingResult>();
  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    ClearError();
    g_pending_results[id] = pending_result;
  }

  g_invoke_action(reinterpret_cast<void *>(&ResultCallback), action.c_str());

  std::unique_lock<std::mutex> lock(pending_result->mutex);
  const bool completed = pending_result->condition.wait_for(
      lock, kInvokeTimeout, [&pending_result]() {
        return pending_result->completed;
      });
  const std::string payload = pending_result->payload;
  lock.unlock();

  {
    std::lock_guard<std::mutex> state_lock(g_state_mutex);
    g_pending_results.erase(id);
    if (!completed) {
      SetError("invokeCore timeout: " + id);
      return "";
    }
  }

  return payload;
}

std::string ReadStringArg(napi_env env, napi_value arg) {
  size_t length = 0;
  napi_get_value_string_utf8(env, arg, nullptr, 0, &length);
  if (length == 0) {
    return "";
  }
  std::string value(length, '\0');
  napi_get_value_string_utf8(env, arg, &value[0], length + 1, &length);
  return value;
}

napi_value InvokeCore(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1] = {nullptr};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc < 1) {
    return CreateString(env, "");
  }
  return CreateString(env, InvokeCoreBlocking(ReadStringArg(env, args[0])));
}

struct AsyncInvokeCoreContext {
  napi_env env = nullptr;
  napi_deferred deferred = nullptr;
  napi_async_work work = nullptr;
  std::string action;
  std::string result;
};

void ExecuteInvokeCore(napi_env env, void *data) {
  auto *context = static_cast<AsyncInvokeCoreContext *>(data);
  context->result = InvokeCoreBlocking(context->action);
}

void CompleteInvokeCore(napi_env env, napi_status status, void *data) {
  auto *context = static_cast<AsyncInvokeCoreContext *>(data);
  napi_value result = CreateString(env, context->result);
  napi_resolve_deferred(env, context->deferred, result);
  napi_delete_async_work(env, context->work);
  delete context;
}

napi_value InvokeCoreAsync(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1] = {nullptr};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  napi_deferred deferred = nullptr;
  napi_value promise = nullptr;
  napi_create_promise(env, &deferred, &promise);
  if (argc < 1) {
    napi_resolve_deferred(env, deferred, CreateString(env, ""));
    return promise;
  }

  auto *context = new AsyncInvokeCoreContext();
  context->env = env;
  context->deferred = deferred;
  context->action = ReadStringArg(env, args[0]);

  napi_value resource_name = CreateString(env, "InvokeCoreAsync");
  const napi_status create_status = napi_create_async_work(
      env, nullptr, resource_name, ExecuteInvokeCore, CompleteInvokeCore,
      context, &context->work);
  if (create_status != napi_ok) {
    delete context;
    napi_resolve_deferred(env, deferred, CreateString(env, ""));
    return promise;
  }
  const napi_status queue_status = napi_queue_async_work(env, context->work);
  if (queue_status != napi_ok) {
    napi_delete_async_work(env, context->work);
    delete context;
    napi_resolve_deferred(env, deferred, CreateString(env, ""));
    return promise;
  }
  return promise;
}

napi_value ChmodPath(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1] = {nullptr};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc < 1) {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    SetError("missing path for chmodPath");
    return CreateBool(env, false);
  }

  size_t path_length = 0;
  napi_get_value_string_utf8(env, args[0], nullptr, 0, &path_length);
  std::string path(path_length, '\0');
  napi_get_value_string_utf8(
      env, args[0], &path[0], path_length + 1, &path_length);

  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    ClearError();
  }
  if (chmod(path.c_str(), 0755) != 0) {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    SetError(std::string("chmod failed: ") + std::strerror(errno));
    return CreateBool(env, false);
  }
  return CreateBool(env, true);
}

napi_value ConsumeCoreEvents(napi_env env, napi_callback_info info) {
  (void)info;
  if (!EnsureCoreLoaded()) {
    return CreateString(env, "[]");
  }
  return CreateString(env, ConsumeQueuedCoreEvents());
}

napi_value StartTun(napi_env env, napi_callback_info info) {
  size_t argc = 4;
  napi_value args[4] = {nullptr, nullptr, nullptr, nullptr};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc < 4) {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    SetError("missing args for startTun");
    return CreateBool(env, false);
  }
  if (!EnsureCoreLoaded()) {
    return CreateBool(env, false);
  }

  int32_t fd = 0;
  napi_get_value_int32(env, args[0], &fd);

  auto readStringArg = [&](napi_value value) {
    size_t value_length = 0;
    napi_get_value_string_utf8(env, value, nullptr, 0, &value_length);
    std::string result(value_length, '\0');
    napi_get_value_string_utf8(
        env, value, &result[0], value_length + 1, &value_length);
    return result;
  };

  std::string stack = readStringArg(args[1]);
  std::string address = readStringArg(args[2]);
  std::string dns = readStringArg(args[3]);

  std::vector<char> stack_buffer(stack.begin(), stack.end());
  stack_buffer.push_back('\0');
  std::vector<char> address_buffer(address.begin(), address.end());
  address_buffer.push_back('\0');
  std::vector<char> dns_buffer(dns.begin(), dns.end());
  dns_buffer.push_back('\0');

  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    ClearError();
  }
  const bool ok = g_start_tun(
      nullptr,
      fd,
      stack_buffer.data(),
      address_buffer.data(),
      dns_buffer.data());
  if (!ok) {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    SetError("startTUN returned false");
  }
  return CreateBool(env, ok);
}

napi_value StopTun(napi_env env, napi_callback_info info) {
  (void)info;
  if (!EnsureCoreLoaded()) {
    return CreateBool(env, false);
  }
  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    ClearError();
  }
  g_stop_tun();
  return CreateBool(env, true);
}

napi_value LastError(napi_env env, napi_callback_info info) {
  std::lock_guard<std::mutex> lock(g_state_mutex);
  return CreateString(env, g_last_error);
}

void ProbeChildProcessStarted(int errCode, OHIPCRemoteProxy *remote_proxy) {
  std::lock_guard<std::mutex> lock(g_probe_mutex);
  g_probe_result = errCode;
  g_probe_completed = true;
  g_probe_condition.notify_one();
  (void)remote_proxy;
}

void HandleChildProcessExit(int32_t pid, int32_t signal) {
  std::lock_guard<std::mutex> lock(g_exit_mutex);
  g_exit_pid = pid;
  g_exit_signal = signal;
  g_exit_received = true;
  g_exit_condition.notify_one();
}

napi_value ProbeCreateNativeChildProcess(napi_env env, napi_callback_info info) {
  {
    std::lock_guard<std::mutex> lock(g_probe_mutex);
    g_probe_completed = false;
    g_probe_result = NCP_ERR_TIMEOUT;
  }

  const auto err = OH_Ability_CreateNativeChildProcess(
      "libentry.so",
      &ProbeChildProcessStarted);
  if (err != NCP_NO_ERROR) {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    ClearError();
    SetError(
        "OH_Ability_CreateNativeChildProcess failed: " +
        std::to_string(err));
    return CreateInt32(env, -err);
  }

  std::unique_lock<std::mutex> probe_lock(g_probe_mutex);
  const bool completed = g_probe_condition.wait_for(
      probe_lock,
      std::chrono::seconds(2),
      []() { return g_probe_completed; });
  const int result = g_probe_result;
  probe_lock.unlock();

  if (!completed) {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    ClearError();
    SetError("OH_Ability_CreateNativeChildProcess probe timeout");
    return CreateInt32(env, -NCP_ERR_TIMEOUT);
  }

  return CreateInt32(env, result == NCP_NO_ERROR ? 0 : -result);
}

napi_value StartCoreChildProcess(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1] = {nullptr};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

  std::vector<char> entry_params;
  if (argc >= 1) {
    size_t value_length = 0;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &value_length);
    entry_params.resize(value_length + 1, '\0');
    napi_get_value_string_utf8(
        env, args[0], entry_params.data(), entry_params.size(), &value_length);
  }

  NativeChildProcess_Args child_args {};
  child_args.entryParams =
      entry_params.empty() ? nullptr : entry_params.data();

  NativeChildProcess_Options options {};
  options.isolationMode = NCP_ISOLATION_MODE_NORMAL;

  {
    std::lock_guard<std::mutex> lock(g_exit_mutex);
    g_exit_received = false;
    g_exit_pid = -1;
    g_exit_signal = 0;
  }
  OH_Ability_RegisterNativeChildProcessExitCallback(&HandleChildProcessExit);

  int32_t pid = -1;
  const auto err = OH_Ability_StartNativeChildProcess(
      "libentry_child.so:FlClashCoreMain",
      child_args,
      options,
      &pid);

  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    ClearError();
    if (err != NCP_NO_ERROR) {
      OH_Ability_UnregisterNativeChildProcessExitCallback(&HandleChildProcessExit);
      SetError(
          "OH_Ability_StartNativeChildProcess failed: " +
          std::to_string(err));
      return CreateInt32(env, -err);
    }
  }

  std::thread([]() {
    std::unique_lock<std::mutex> lock(g_exit_mutex);
    const bool received = g_exit_condition.wait_for(
        lock,
        std::chrono::seconds(20),
        []() { return g_exit_received; });
    const auto pid = g_exit_pid;
    const auto signal = g_exit_signal;
    lock.unlock();
    if (received) {
      AppendEarlyDebugLog(
          "child exit callback pid=" + std::to_string(pid) + " signal=" +
          std::to_string(signal));
    } else {
      AppendEarlyDebugLog("child exit callback timeout");
    }
    OH_Ability_UnregisterNativeChildProcessExitCallback(&HandleChildProcessExit);
  }).detach();

  return CreateInt32(env, pid);
}

napi_value StartBundledCoreProcess(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2] = {nullptr, nullptr};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc < 2) {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    SetError("missing sourcePath or socketPath for startBundledCoreProcess");
    return CreateInt32(env, -1);
  }

  auto readStringArg = [&](napi_value value) {
    size_t value_length = 0;
    napi_get_value_string_utf8(env, value, nullptr, 0, &value_length);
    std::string result(value_length, '\0');
    napi_get_value_string_utf8(
        env, value, &result[0], value_length + 1, &value_length);
    return result;
  };

  const std::string source_path = readStringArg(args[0]);
  const std::string socket_path = readStringArg(args[1]);
  const std::string debug_log_path =
      JoinPath(DirName(source_path), "flclash-bridge.log");
  const std::string core_debug_log_path =
      JoinPath(DirName(source_path), "flclash-core.log");

  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    ClearError();
  }
  AppendDebugLog(
      debug_log_path,
      "startBundledCoreProcess source=" + source_path + " socket=" + socket_path);
  if (chmod(source_path.c_str(), 0755) != 0) {
    AppendDebugLog(
        debug_log_path,
        std::string("chmod source failed: ") + std::strerror(errno));
    std::lock_guard<std::mutex> lock(g_state_mutex);
    SetError(std::string("chmod source failed: ") + std::strerror(errno));
    return CreateInt32(env, -1);
  }
  AppendDebugLog(debug_log_path, "chmod source ok");

  const pid_t pid = fork();
  if (pid < 0) {
    AppendDebugLog(
        debug_log_path,
        std::string("fork failed: ") + std::strerror(errno));
    std::lock_guard<std::mutex> lock(g_state_mutex);
    SetError(std::string("fork failed: ") + std::strerror(errno));
    return CreateInt32(env, -1);
  }

  if (pid == 0) {
    AppendDebugLog(debug_log_path, "child process entered");
    std::vector<char *> argv;
    argv.push_back(const_cast<char *>(source_path.c_str()));
    if (!socket_path.empty()) {
      argv.push_back(const_cast<char *>(socket_path.c_str()));
    }
    argv.push_back(const_cast<char *>(core_debug_log_path.c_str()));
    argv.push_back(nullptr);
    execv(source_path.c_str(), argv.data());
    AppendDebugLog(
        debug_log_path,
        std::string("execv source failed: ") + std::strerror(errno));
    std::fprintf(
        stderr,
        "[OHOS-CORE] source exec failed: %s\n",
        std::strerror(errno));
    std::fflush(stderr);
    _exit(127);
  }

  AppendDebugLog(debug_log_path, "fork ok pid=" + std::to_string(pid));
  return CreateInt32(env, pid);
}

}  // namespace

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor desc[] = {
      {"invokeCore", nullptr, InvokeCore, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"invokeCoreAsync", nullptr, InvokeCoreAsync, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"consumeCoreEvents", nullptr, ConsumeCoreEvents, nullptr, nullptr,
       nullptr, napi_default, nullptr},
      {"chmodPath", nullptr, ChmodPath, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"probeCreateNativeChildProcess", nullptr, ProbeCreateNativeChildProcess,
       nullptr, nullptr, nullptr, napi_default, nullptr},
      {"startCoreChildProcess", nullptr, StartCoreChildProcess, nullptr,
       nullptr, nullptr, napi_default, nullptr},
      {"startBundledCoreProcess", nullptr, StartBundledCoreProcess, nullptr,
       nullptr, nullptr, napi_default, nullptr},
      {"lastError", nullptr, LastError, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"startTun", nullptr, StartTun, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"stopTun", nullptr, StopTun, nullptr, nullptr, nullptr,
       napi_default, nullptr},
  };
  napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
  return exports;
}
EXTERN_C_END

static napi_module entryModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "entry",
    .nm_priv = ((void *)0),
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void) {
  napi_module_register(&entryModule);
}

extern "C" __attribute__((constructor)) void TraceEntryLibraryLoad(void) {
  AppendEarlyDebugLog("libentry loaded pid=" + std::to_string(getpid()));
}

extern "C" __attribute__((visibility("default"))) OHIPCRemoteStub *
NativeChildProcess_OnConnect(void) {
  AppendEarlyDebugLog(
      "NativeChildProcess_OnConnect pid=" + std::to_string(getpid()));
  return nullptr;
}

extern "C" __attribute__((visibility("default"))) void NativeChildProcess_MainProc(
    void) {
  AppendEarlyDebugLog(
      "NativeChildProcess_MainProc pid=" + std::to_string(getpid()));
}

extern "C" __attribute__((visibility("default"))) void FlClashCoreMain(
    NativeChildProcess_Args args) {
  const std::string entry_params =
      args.entryParams == nullptr ? std::string() : std::string(args.entryParams);
  const std::string debug_log_path = BuildChildDebugLogPath(entry_params);
  AppendDebugLog(debug_log_path, "FlClashCoreMain entry socket=" + entry_params);
  LogChildProcess("bridge FlClashCoreMain entry socket=" + entry_params);
}
