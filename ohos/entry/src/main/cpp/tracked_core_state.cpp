#include "tracked_core_state.h"

uint64_t TrackedCoreState::Track(CoreLaunchMode mode, int32_t pid) {
  std::lock_guard<std::mutex> lock(mutex_);
  current_.mode = mode;
  current_.pid = pid;
  current_.token = nextToken_++;
  current_.embeddedStarted = mode == CoreLaunchMode::kEmbedded;
  return current_.token;
}

bool TrackedCoreState::TryTrackEmbedded(uint64_t *token) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (current_.mode != CoreLaunchMode::kNone || current_.embeddedStarted) {
    return false;
  }
  current_.mode = CoreLaunchMode::kEmbedded;
  current_.pid = -1;
  current_.token = nextToken_++;
  current_.embeddedStarted = true;
  if (token != nullptr) {
    *token = current_.token;
  }
  return true;
}

TrackedCoreSnapshot TrackedCoreState::Current() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return current_;
}

void TrackedCoreState::Clear() {
  std::lock_guard<std::mutex> lock(mutex_);
  current_ = {};
}

bool TrackedCoreState::ClearIfMatches(
    CoreLaunchMode mode,
    int32_t pid,
    uint64_t token) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (current_.mode != mode) {
    return false;
  }
  if (token != 0 && current_.token != token) {
    return false;
  }
  if (pid > 0 && current_.pid != pid) {
    return false;
  }
  current_ = {};
  return true;
}
