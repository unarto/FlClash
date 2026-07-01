#include "tracked_core_state.h"

#include <cassert>

int main() {
  TrackedCoreState state;

  const auto stale_child_token = state.Track(CoreLaunchMode::kChild, 101);
  const auto current_child_token = state.Track(CoreLaunchMode::kChild, 202);
  assert(!state.ClearIfMatches(
      CoreLaunchMode::kChild,
      101,
      stale_child_token));
  {
    const auto current = state.Current();
    assert(current.mode == CoreLaunchMode::kChild);
    assert(current.pid == 202);
    assert(current.token == current_child_token);
  }

  const auto stale_embedded_token = state.Track(CoreLaunchMode::kEmbedded);
  const auto current_embedded_token = state.Track(CoreLaunchMode::kEmbedded);
  assert(!state.ClearIfMatches(
      CoreLaunchMode::kEmbedded,
      -1,
      stale_embedded_token));
  {
    const auto current = state.Current();
    assert(current.mode == CoreLaunchMode::kEmbedded);
    assert(current.pid == -1);
    assert(current.token == current_embedded_token);
  }

  assert(state.ClearIfMatches(
      CoreLaunchMode::kEmbedded,
      -1,
      current_embedded_token));
  {
    const auto current = state.Current();
    assert(current.mode == CoreLaunchMode::kNone);
    assert(current.pid == -1);
  }

  const auto child_token = state.Track(CoreLaunchMode::kChild, 303);
  uint64_t embedded_token = 0;
  assert(!state.TryTrackEmbedded(&embedded_token));
  {
    const auto current = state.Current();
    assert(current.mode == CoreLaunchMode::kChild);
    assert(current.pid == 303);
    assert(current.token == child_token);
    assert(!current.embeddedStarted);
  }
  state.Clear();

  const auto bundled_token = state.Track(CoreLaunchMode::kBundled, 404);
  assert(!state.TryTrackEmbedded(&embedded_token));
  {
    const auto current = state.Current();
    assert(current.mode == CoreLaunchMode::kBundled);
    assert(current.pid == 404);
    assert(current.token == bundled_token);
    assert(!current.embeddedStarted);
  }

  return 0;
}
