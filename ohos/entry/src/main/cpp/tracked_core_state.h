#pragma once

#include <cstdint>
#include <mutex>

enum class CoreLaunchMode {
  kNone,
  kChild,
  kBundled,
  kEmbedded,
};

struct TrackedCoreSnapshot {
  CoreLaunchMode mode = CoreLaunchMode::kNone;
  int32_t pid = -1;
  uint64_t token = 0;
  bool embeddedStarted = false;
};

class TrackedCoreState {
 public:
  uint64_t Track(CoreLaunchMode mode, int32_t pid = -1);
  bool TryTrackEmbedded(uint64_t *token);
  TrackedCoreSnapshot Current() const;
  void Clear();
  bool ClearIfMatches(CoreLaunchMode mode, int32_t pid, uint64_t token);

 private:
  mutable std::mutex mutex_;
  TrackedCoreSnapshot current_;
  uint64_t nextToken_ = 1;
};
