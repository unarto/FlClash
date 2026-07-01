#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <sys/mman.h>
#include <arpa/inet.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <condition_variable>
#include <cctype>
#include <cstdint>
#include <memory>
#include <mutex>
#include <netinet/in.h>
#include <poll.h>
#include <string>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include <AbilityKit/native_child_process.h>
#include <hilog/log.h>
#include "napi/native_api.h"
#include "tracked_core_state.h"

namespace {

using InvokeActionFn = void (*)(void *, const char *);
using FreeCStringFn = void (*)(char *);
using SetEventListenerFn = void (*)(void *);
using QuickSetupFn = void (*)(void *, char *, char *);
using StartTunFn = bool (*)(void *, int, char *, char *, char *);
using StopTunFn = void (*)();
using StartServerProcessFn = void (*)(char *, char *);
using StartServerProcessDetachedFn = void (*)(char *, char *);
using StopServerProcessDetachedFn = void (*)();
using ProtectBridgeFn = void (*)(void *, int);
using ResolveProcessBridgeFn =
    char *(*)(void *, int, const char *, const char *, int);

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
QuickSetupFn g_quick_setup = nullptr;
StartTunFn g_start_tun = nullptr;
StopTunFn g_stop_tun = nullptr;
bool g_event_listener_registered = false;
std::thread g_embedded_core_thread;
std::mutex g_state_mutex;
std::vector<std::string> g_event_payloads;
StopServerProcessDetachedFn g_stop_server_process_detached = nullptr;
TrackedCoreState g_tracked_core_state;
bool g_child_exit_callback_registered = false;

struct PendingResult {
  std::mutex mutex;
  std::condition_variable condition;
  bool completed = false;
  std::string payload;
};

struct QuickSetupResult {
  std::mutex mutex;
  std::condition_variable condition;
  bool completed = false;
  std::string payload;
};

struct ProtectRequest {
  int32_t id = 0;
  int32_t fd = -1;
  std::mutex mutex;
  std::condition_variable condition;
  bool completed = false;
  int32_t result = -1;
};

void ResultCallback(const char *data);
void QuickSetupCallback(const char *data);
QuickSetupResult *g_quick_setup_result = nullptr;

std::unordered_map<std::string, std::shared_ptr<PendingResult>> g_pending_results;
std::unordered_set<std::string> g_detached_ids;
ProtectBridgeFn *g_protect_bridge = nullptr;
ResolveProcessBridgeFn *g_resolve_process_bridge = nullptr;
char g_tun_callback_token = 0;
std::mutex g_protect_requests_mutex;
std::unordered_map<int32_t, std::shared_ptr<ProtectRequest>> g_protect_requests;
std::vector<int32_t> g_pending_protect_request_ids;
int32_t g_next_protect_request_id = 1;
std::mutex g_probe_mutex;
std::condition_variable g_probe_condition;
bool g_probe_completed = false;
int g_probe_result = NCP_ERR_TIMEOUT;

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

void ProtectSocketFromVpn(void *, int fd) {
  if (fd < 0) {
    AppendEarlyDebugLog("protect socket skipped invalid fd=" +
                        std::to_string(fd));
    return;
  }

  auto request = std::make_shared<ProtectRequest>();
  {
    std::lock_guard<std::mutex> lock(g_protect_requests_mutex);
    request->id = g_next_protect_request_id++;
    request->fd = fd;
    g_protect_requests[request->id] = request;
    g_pending_protect_request_ids.push_back(request->id);
  }

  AppendEarlyDebugLog(
      "protect socket queued id=" + std::to_string(request->id) +
      " fd=" + std::to_string(fd));

  std::unique_lock<std::mutex> lock(request->mutex);
  const bool completed = request->condition.wait_for(
      lock, kInvokeTimeout, [&request]() {
        return request->completed;
      });
  const auto result = request->result;
  lock.unlock();

  {
    std::lock_guard<std::mutex> requests_lock(g_protect_requests_mutex);
    g_protect_requests.erase(request->id);
  }

  if (!completed) {
    AppendEarlyDebugLog(
        "protect socket timeout id=" + std::to_string(request->id) +
        " fd=" + std::to_string(fd));
    return;
  }

  AppendEarlyDebugLog(
      "protect socket completed id=" + std::to_string(request->id) +
      " fd=" + std::to_string(fd) +
      " result=" + std::to_string(result));
}

char *ResolveProcessNoop(void *, int, const char *, const char *, int) {
  return nullptr;
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
  if (g_invoke_action != nullptr && g_quick_setup != nullptr &&
      g_start_tun != nullptr &&
      g_stop_tun != nullptr &&
      g_stop_server_process_detached != nullptr) {
    return true;
  }
  std::lock_guard<std::mutex> lock(g_state_mutex);
  if (g_invoke_action != nullptr && g_quick_setup != nullptr &&
      g_start_tun != nullptr &&
      g_stop_tun != nullptr &&
      g_stop_server_process_detached != nullptr) {
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
  auto quick_setup_symbol = dlsym(g_core_handle, "quickSetup");
  if (quick_setup_symbol == nullptr) {
    const char *error = dlerror();
    g_invoke_action = nullptr;
    g_free_c_string = nullptr;
    g_set_event_listener = nullptr;
    return SetError(error == nullptr ? "dlsym quickSetup failed" : error);
  }
  g_quick_setup = reinterpret_cast<QuickSetupFn>(quick_setup_symbol);
  auto start_tun_symbol = dlsym(g_core_handle, "startTUN");
  if (start_tun_symbol == nullptr) {
    const char *error = dlerror();
    g_invoke_action = nullptr;
    g_free_c_string = nullptr;
    g_set_event_listener = nullptr;
    g_quick_setup = nullptr;
    return SetError(error == nullptr ? "dlsym startTUN failed" : error);
  }
  g_start_tun = reinterpret_cast<StartTunFn>(start_tun_symbol);
  auto stop_tun_symbol = dlsym(g_core_handle, "stopTun");
  if (stop_tun_symbol == nullptr) {
    const char *error = dlerror();
    g_invoke_action = nullptr;
    g_free_c_string = nullptr;
    g_set_event_listener = nullptr;
    g_quick_setup = nullptr;
    g_start_tun = nullptr;
    return SetError(error == nullptr ? "dlsym stopTun failed" : error);
  }
  g_stop_tun = reinterpret_cast<StopTunFn>(stop_tun_symbol);
  auto stop_server_symbol = dlsym(g_core_handle, "stopServerProcessDetached");
  if (stop_server_symbol == nullptr) {
    const char *error = dlerror();
    g_invoke_action = nullptr;
    g_free_c_string = nullptr;
    g_set_event_listener = nullptr;
    g_quick_setup = nullptr;
    g_start_tun = nullptr;
    g_stop_tun = nullptr;
    return SetError(
        error == nullptr ? "dlsym stopServerProcessDetached failed" : error);
  }
  g_stop_server_process_detached =
      reinterpret_cast<StopServerProcessDetachedFn>(stop_server_symbol);
  auto protect_symbol = dlsym(g_core_handle, "protect_func");
  if (protect_symbol != nullptr) {
    g_protect_bridge = reinterpret_cast<ProtectBridgeFn *>(protect_symbol);
    *g_protect_bridge = &ProtectSocketFromVpn;
  }
  auto resolve_symbol = dlsym(g_core_handle, "resolve_process_func");
  if (resolve_symbol != nullptr) {
    g_resolve_process_bridge =
        reinterpret_cast<ResolveProcessBridgeFn *>(resolve_symbol);
    *g_resolve_process_bridge = &ResolveProcessNoop;
  }
  if (g_set_event_listener != nullptr && !g_event_listener_registered) {
    g_set_event_listener(reinterpret_cast<void *>(&ResultCallback));
    g_event_listener_registered = true;
  }
  return true;
}

uint64_t TrackCoreLaunch(CoreLaunchMode mode, int32_t pid = -1) {
  return g_tracked_core_state.Track(mode, pid);
}

void ClearTrackedCoreLaunch() {
  g_tracked_core_state.Clear();
}

bool ClearTrackedCoreLaunchIfMatches(
    CoreLaunchMode mode,
    int32_t pid,
    uint64_t token) {
  return g_tracked_core_state.ClearIfMatches(mode, pid, token);
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

void QuickSetupCallback(const char *data) {
  QuickSetupResult *result = nullptr;
  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    result = g_quick_setup_result;
  }
  if (result == nullptr) {
    return;
  }
  {
    std::lock_guard<std::mutex> lock(result->mutex);
    if (data != nullptr) {
      result->payload = data;
    }
    result->completed = true;
  }
  result->condition.notify_one();
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
  if (method == "getIsInit") {
    AppendEarlyDebugLog("InvokeCoreBlocking getIsInit begin id=" + id +
                        " action=" + action);
  }
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
  if (method == "getIsInit") {
    AppendEarlyDebugLog("InvokeCoreBlocking getIsInit invokeAction returned id=" +
                        id);
  }

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
      if (method == "getIsInit") {
        AppendEarlyDebugLog("InvokeCoreBlocking getIsInit timeout id=" + id);
      }
      return "";
    }
  }

  if (method == "getIsInit") {
    AppendEarlyDebugLog("InvokeCoreBlocking getIsInit completed id=" + id +
                        " payload=" + payload);
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

  int fd_flags = fcntl(fd, F_GETFL);
  int fd_error = errno;
  AppendEarlyDebugLog(
      "StartTun request fd=" + std::to_string(fd) +
      " flags=" + std::to_string(fd_flags) +
      " fdErrno=" + std::to_string(fd_error) +
      " stack=" + stack +
      " address=" + address +
      " dns=" + dns);

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
      reinterpret_cast<void *>(&g_tun_callback_token),
      fd,
      stack_buffer.data(),
      address_buffer.data(),
      dns_buffer.data());
  AppendEarlyDebugLog(
      "StartTun result ok=" + std::to_string(ok ? 1 : 0) +
      " fd=" + std::to_string(fd) +
      " lastError=" + g_last_error);
  if (!ok) {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    SetError("startTUN returned false");
  }
  return CreateBool(env, ok);
}

napi_value QuickSetup(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2] = {nullptr, nullptr};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc < 2) {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    SetError("missing init/setup params for quickSetup");
    return CreateString(env, "missing init/setup params");
  }
  if (!EnsureCoreLoaded()) {
    return CreateString(env, "");
  }

  std::string init_params = ReadStringArg(env, args[0]);
  std::string setup_params = ReadStringArg(env, args[1]);
  std::vector<char> init_params_buffer(init_params.begin(), init_params.end());
  init_params_buffer.push_back('\0');
  std::vector<char> setup_params_buffer(setup_params.begin(), setup_params.end());
  setup_params_buffer.push_back('\0');

  QuickSetupResult quick_setup_result;
  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    ClearError();
    g_quick_setup_result = &quick_setup_result;
  }
  AppendEarlyDebugLog("QuickSetup begin");
  g_quick_setup(
      reinterpret_cast<void *>(&QuickSetupCallback),
      init_params_buffer.data(),
      setup_params_buffer.data());

  std::unique_lock<std::mutex> lock(quick_setup_result.mutex);
  const bool completed = quick_setup_result.condition.wait_for(
      lock, kInvokeTimeout, [&quick_setup_result]() {
        return quick_setup_result.completed;
      });
  const std::string payload = quick_setup_result.payload;
  lock.unlock();

  {
    std::lock_guard<std::mutex> state_lock(g_state_mutex);
    g_quick_setup_result = nullptr;
    if (!completed) {
      SetError("quickSetup timeout");
      AppendEarlyDebugLog("QuickSetup timeout");
      return CreateString(env, "quickSetup timeout");
    }
  }
  AppendEarlyDebugLog("QuickSetup done payload=" + payload);
  return CreateString(env, payload);
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

napi_value ConsumeProtectRequests(napi_env env, napi_callback_info info) {
  (void)info;
  std::vector<std::shared_ptr<ProtectRequest>> requests;
  {
    std::lock_guard<std::mutex> lock(g_protect_requests_mutex);
    for (const auto id : g_pending_protect_request_ids) {
      auto it = g_protect_requests.find(id);
      if (it != g_protect_requests.end()) {
        requests.push_back(it->second);
      }
    }
    g_pending_protect_request_ids.clear();
  }
  if (requests.empty()) {
    return CreateString(env, "[]");
  }

  std::string payload = "[";
  for (size_t index = 0; index < requests.size(); ++index) {
    if (index > 0) {
      payload += ",";
    }
    payload += "{\"id\":";
    payload += std::to_string(requests[index]->id);
    payload += ",\"fd\":";
    payload += std::to_string(requests[index]->fd);
    payload += "}";
  }
  payload += "]";
  return CreateString(env, payload);
}

napi_value CompleteProtectRequest(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2] = {nullptr, nullptr};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc < 2) {
    return CreateBool(env, false);
  }

  int32_t request_id = 0;
  int32_t result = -1;
  napi_get_value_int32(env, args[0], &request_id);
  napi_get_value_int32(env, args[1], &result);

  std::shared_ptr<ProtectRequest> request;
  {
    std::lock_guard<std::mutex> lock(g_protect_requests_mutex);
    auto it = g_protect_requests.find(request_id);
    if (it == g_protect_requests.end()) {
      return CreateBool(env, false);
    }
    request = it->second;
  }

  {
    std::lock_guard<std::mutex> lock(request->mutex);
    request->result = result;
    request->completed = true;
  }
  request->condition.notify_all();
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
  AppendEarlyDebugLog(
      "child exit callback pid=" + std::to_string(pid) + " signal=" +
      std::to_string(signal));
  const bool cleared = ClearTrackedCoreLaunchIfMatches(
      CoreLaunchMode::kChild,
      pid,
      0);
  AppendEarlyDebugLog(
      "child exit callback cleared=" + std::string(cleared ? "true" : "false"));
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
    std::lock_guard<std::mutex> lock(g_state_mutex);
    if (!g_child_exit_callback_registered) {
      OH_Ability_RegisterNativeChildProcessExitCallback(&HandleChildProcessExit);
      g_child_exit_callback_registered = true;
    }
  }

  int32_t pid = -1;
  const auto err = OH_Ability_StartNativeChildProcess(
      "libentry.so:FlClashCoreMain",
      child_args,
      options,
      &pid);

  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    ClearError();
    if (err != NCP_NO_ERROR) {
      SetError(
          "OH_Ability_StartNativeChildProcess failed: " +
          std::to_string(err));
      return CreateInt32(env, -err);
    }
  }

  TrackCoreLaunch(CoreLaunchMode::kChild, pid);
  errno = 0;
  if (waitpid(pid, nullptr, WNOHANG) == pid || kill(pid, 0) != 0) {
    ClearTrackedCoreLaunchIfMatches(
        CoreLaunchMode::kChild,
        pid,
        0);
    std::lock_guard<std::mutex> lock(g_state_mutex);
    SetError("native child process exited before startup completed");
    return CreateInt32(env, -1);
  }
  return CreateInt32(env, pid);
}

napi_value StartBundledCoreProcess(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value args[3] = {nullptr, nullptr, nullptr};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc < 3) {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    SetError(
        "missing sourcePath, socketPath or logDirPath for startBundledCoreProcess");
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
  const std::string log_dir_path = readStringArg(args[2]);
  const std::string debug_log_path = JoinPath(log_dir_path, "flclash-bridge.log");
  const std::string core_debug_log_path = JoinPath(log_dir_path, "flclash-core.log");

  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    ClearError();
  }
  AppendDebugLog(
      debug_log_path,
      "startBundledCoreProcess source=" + source_path + " socket=" + socket_path +
          " logDir=" + log_dir_path);
  errno = 0;
  struct stat source_stat {};
  const int stat_result = stat(source_path.c_str(), &source_stat);
  const int stat_errno = errno;
  AppendDebugLog(
      debug_log_path,
      "source stat result=" + std::to_string(stat_result) +
          " errno=" + std::to_string(stat_errno) +
          " mode=" + std::to_string(static_cast<unsigned int>(source_stat.st_mode)) +
          " size=" + std::to_string(static_cast<long long>(source_stat.st_size)));
  errno = 0;
  const int access_exists = access(source_path.c_str(), F_OK);
  const int access_exists_errno = errno;
  AppendDebugLog(
      debug_log_path,
      "source access F_OK=" + std::to_string(access_exists) +
          " errno=" + std::to_string(access_exists_errno));
  errno = 0;
  const int access_exec = access(source_path.c_str(), X_OK);
  const int access_exec_errno = errno;
  AppendDebugLog(
      debug_log_path,
      "source access X_OK=" + std::to_string(access_exec) +
          " errno=" + std::to_string(access_exec_errno));
  if (chmod(source_path.c_str(), 0755) != 0) {
    AppendDebugLog(
        debug_log_path,
        std::string("chmod source failed: ") + std::strerror(errno));
    std::lock_guard<std::mutex> lock(g_state_mutex);
    SetError(std::string("chmod source failed: ") + std::strerror(errno));
    return CreateInt32(env, -1);
  }
  AppendDebugLog(debug_log_path, "chmod source ok");
  errno = 0;
  const int post_chmod_exec = access(source_path.c_str(), X_OK);
  const int post_chmod_exec_errno = errno;
  AppendDebugLog(
      debug_log_path,
      "source access X_OK after chmod=" + std::to_string(post_chmod_exec) +
          " errno=" + std::to_string(post_chmod_exec_errno));

  pid_t pid = -1;
  std::vector<char *> argv;
  argv.push_back(const_cast<char *>(source_path.c_str()));
  if (!socket_path.empty()) {
    argv.push_back(const_cast<char *>(socket_path.c_str()));
  }
  argv.push_back(const_cast<char *>(core_debug_log_path.c_str()));
  argv.push_back(nullptr);

  const int spawn_err = posix_spawn(
      &pid,
      source_path.c_str(),
      nullptr,
      nullptr,
      argv.data(),
      nullptr);
  if (spawn_err != 0) {
    AppendDebugLog(
        debug_log_path,
        std::string("posix_spawn failed: ") + std::strerror(spawn_err) +
            " code=" + std::to_string(spawn_err));
    std::lock_guard<std::mutex> lock(g_state_mutex);
    SetError(
        std::string("posix_spawn failed: ") + std::strerror(spawn_err) +
        " code=" + std::to_string(spawn_err));
    return CreateInt32(env, -1);
  }

  AppendDebugLog(debug_log_path, "posix_spawn ok pid=" + std::to_string(pid));
  TrackCoreLaunch(CoreLaunchMode::kBundled, pid);
  errno = 0;
  if (waitpid(pid, nullptr, WNOHANG) == pid || kill(pid, 0) != 0) {
    ClearTrackedCoreLaunchIfMatches(
        CoreLaunchMode::kBundled,
        pid,
        0);
    std::lock_guard<std::mutex> lock(g_state_mutex);
    SetError("bundled core process exited before startup completed");
    return CreateInt32(env, -1);
  }
  return CreateInt32(env, pid);
}

napi_value StartEmbeddedCore(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2] = {nullptr, nullptr};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc < 2) {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    SetError("missing socketPath or logDirPath for startEmbeddedCore");
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

  const std::string socket_path = readStringArg(args[0]);
  const std::string log_dir_path = readStringArg(args[1]);
  const std::string debug_log_path = JoinPath(log_dir_path, "flclash-bridge.log");
  const std::string core_log_path = JoinPath(log_dir_path, "flclash-core.log");

  uint64_t embedded_launch_token = 0;
  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    ClearError();
  }
  if (!g_tracked_core_state.TryTrackEmbedded(&embedded_launch_token)) {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    SetError("embedded core already started");
    return CreateInt32(env, -1);
  }

  AppendDebugLog(
      debug_log_path,
      "startEmbeddedCore socket=" + socket_path + " logDir=" + log_dir_path);
  dlerror();
  void *core_handle = dlopen("libclash.so", RTLD_NOW | RTLD_LOCAL);
  if (core_handle == nullptr) {
    const char *error = dlerror();
    const std::string message =
        "startEmbeddedCore dlopen libclash.so failed: " +
        std::string(error == nullptr ? "unknown" : error);
    ClearTrackedCoreLaunchIfMatches(
        CoreLaunchMode::kEmbedded,
        -1,
        embedded_launch_token);
    AppendDebugLog(debug_log_path, message);
    std::lock_guard<std::mutex> lock(g_state_mutex);
    SetError(message);
    return CreateInt32(env, -1);
  }

  auto *start_server_process = reinterpret_cast<StartServerProcessDetachedFn>(
      dlsym(core_handle, "startServerProcessDetached"));
  if (start_server_process == nullptr) {
    const char *error = dlerror();
    const std::string message =
        "startEmbeddedCore dlsym startServerProcessDetached failed: " +
        std::string(error == nullptr ? "unknown" : error);
    ClearTrackedCoreLaunchIfMatches(
        CoreLaunchMode::kEmbedded,
        -1,
        embedded_launch_token);
    AppendDebugLog(debug_log_path, message);
    dlclose(core_handle);
    std::lock_guard<std::mutex> lock(g_state_mutex);
    SetError(message);
    return CreateInt32(env, -1);
  }

  g_embedded_core_thread = std::thread(
      [socket_path,
       core_log_path,
       start_server_process,
       debug_log_path]() {
        AppendDebugLog(debug_log_path, "embedded core thread start");
        std::vector<char> socket_path_buffer(socket_path.begin(), socket_path.end());
        socket_path_buffer.push_back('\0');
        std::vector<char> core_log_path_buffer(core_log_path.begin(), core_log_path.end());
        core_log_path_buffer.push_back('\0');

        // startServerProcessDetached is non-blocking: it spawns its own detached
        // goroutine (with panic recovery + generation guard) and returns at once.
        // The core therefore stays live after this returns, so we must NOT dlclose
        // the library or clear the tracked-core state here — doing so wiped the
        // embedded tracking milliseconds after launch, turning StopTrackedCore into
        // a silent no-op and allowing a second embedded core to start over the first.
        // The library stays loaded via g_core_handle; StopTrackedCore is the sole
        // owner of stopping and clearing the embedded launch.
        AppendDebugLog(debug_log_path, "embedded core startServerProcessDetached enter");
        start_server_process(
            socket_path.empty() ? nullptr : socket_path_buffer.data(),
            core_log_path.empty() ? nullptr : core_log_path_buffer.data());
        AppendDebugLog(debug_log_path, "embedded core startServerProcessDetached returned");
      });
  g_embedded_core_thread.detach();
  return CreateInt32(env, 1);
}

napi_value StopTrackedCore(napi_env env, napi_callback_info info) {
  (void)info;
  auto tracked_core = TrackedCoreSnapshot {};
  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    ClearError();
  }
  tracked_core = g_tracked_core_state.Current();

  if (tracked_core.mode == CoreLaunchMode::kNone) {
    return CreateBool(env, true);
  }

  if (tracked_core.mode == CoreLaunchMode::kEmbedded) {
    if (!EnsureCoreLoaded()) {
      return CreateBool(env, false);
    }
    if (g_stop_server_process_detached == nullptr) {
      std::lock_guard<std::mutex> lock(g_state_mutex);
      SetError("stopServerProcessDetached unavailable");
      return CreateBool(env, false);
    }
    g_stop_server_process_detached();
    ClearTrackedCoreLaunchIfMatches(
        tracked_core.mode,
        tracked_core.pid,
        tracked_core.token);
    return CreateBool(env, true);
  }

  if (tracked_core.pid <= 0) {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    SetError("tracked core pid unavailable");
    return CreateBool(env, false);
  }

  if (tracked_core.mode == CoreLaunchMode::kChild) {
#if __OHOS_API__ >= 22
    const auto err = OH_Ability_KillChildProcess(tracked_core.pid);
    if (err != NCP_NO_ERROR && err != NCP_ERR_INVALID_PID) {
      std::lock_guard<std::mutex> lock(g_state_mutex);
      SetError("OH_Ability_KillChildProcess failed: " + std::to_string(err));
      return CreateBool(env, false);
    }
#else
    if (kill(tracked_core.pid, SIGTERM) != 0 && errno != ESRCH) {
      std::lock_guard<std::mutex> lock(g_state_mutex);
      SetError(std::string("kill child process failed: ") + std::strerror(errno));
      return CreateBool(env, false);
    }
#endif
    errno = 0;
    if (waitpid(tracked_core.pid, nullptr, 0) != tracked_core.pid &&
        errno != ECHILD) {
      std::lock_guard<std::mutex> lock(g_state_mutex);
      SetError(std::string("waitpid child process failed: ") + std::strerror(errno));
      return CreateBool(env, false);
    }
    ClearTrackedCoreLaunchIfMatches(
        tracked_core.mode,
        tracked_core.pid,
        tracked_core.token);
    return CreateBool(env, true);
  }

  if (kill(tracked_core.pid, SIGTERM) != 0 && errno != ESRCH) {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    SetError(std::string("kill bundled process failed: ") + std::strerror(errno));
    return CreateBool(env, false);
  }

  for (int attempt = 0; attempt < 20; ++attempt) {
    if (waitpid(tracked_core.pid, nullptr, WNOHANG) == tracked_core.pid ||
        kill(tracked_core.pid, 0) != 0) {
      ClearTrackedCoreLaunchIfMatches(
          tracked_core.mode,
          tracked_core.pid,
          tracked_core.token);
      return CreateBool(env, true);
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
  }

  if (kill(tracked_core.pid, SIGKILL) != 0 && errno != ESRCH) {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    SetError(std::string("force kill bundled process failed: ") + std::strerror(errno));
    return CreateBool(env, false);
  }

  errno = 0;
  if (waitpid(tracked_core.pid, nullptr, 0) != tracked_core.pid &&
      errno != ECHILD) {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    SetError(std::string("waitpid bundled process failed: ") + std::strerror(errno));
    return CreateBool(env, false);
  }

  ClearTrackedCoreLaunchIfMatches(
      tracked_core.mode,
      tracked_core.pid,
      tracked_core.token);
  return CreateBool(env, true);
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
      {"startEmbeddedCore", nullptr, StartEmbeddedCore, nullptr, nullptr,
       nullptr, napi_default, nullptr},
      {"stopTrackedCore", nullptr, StopTrackedCore, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"quickSetup", nullptr, QuickSetup, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"lastError", nullptr, LastError, nullptr, nullptr, nullptr,
       napi_default, nullptr},
      {"consumeProtectRequests", nullptr, ConsumeProtectRequests, nullptr,
       nullptr, nullptr, napi_default, nullptr},
      {"completeProtectRequest", nullptr, CompleteProtectRequest, nullptr,
       nullptr, nullptr, napi_default, nullptr},
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
  const std::string core_log_path = BuildChildCoreLogPath(entry_params);
  AppendDebugLog(debug_log_path, "FlClashCoreMain entry socket=" + entry_params);
  LogChildProcess("bridge FlClashCoreMain entry socket=" + entry_params);

  dlerror();
  void *core_handle = dlopen("libclash.so", RTLD_NOW | RTLD_LOCAL);
  if (core_handle == nullptr) {
    const char *error = dlerror();
    const std::string message =
        "FlClashCoreMain dlopen libclash.so failed: " +
        std::string(error == nullptr ? "unknown" : error);
    AppendDebugLog(debug_log_path, message);
    LogChildProcess(message);
    return;
  }

  auto *start_server_process = reinterpret_cast<StartServerProcessFn>(
      dlsym(core_handle, "startServerProcess"));
  if (start_server_process == nullptr) {
    const char *error = dlerror();
    const std::string message =
        "FlClashCoreMain dlsym startServerProcess failed: " +
        std::string(error == nullptr ? "unknown" : error);
    AppendDebugLog(debug_log_path, message);
    LogChildProcess(message);
    dlclose(core_handle);
    return;
  }

  std::vector<char> entry_params_buffer(entry_params.begin(), entry_params.end());
  entry_params_buffer.push_back('\0');
  std::vector<char> core_log_path_buffer(core_log_path.begin(), core_log_path.end());
  core_log_path_buffer.push_back('\0');

  start_server_process(
      entry_params.empty() ? nullptr : entry_params_buffer.data(),
      core_log_path.empty() ? nullptr : core_log_path_buffer.data());

  AppendDebugLog(debug_log_path, "FlClashCoreMain startServerProcess returned");
  LogChildProcess("bridge FlClashCoreMain startServerProcess returned");
  dlclose(core_handle);
}
