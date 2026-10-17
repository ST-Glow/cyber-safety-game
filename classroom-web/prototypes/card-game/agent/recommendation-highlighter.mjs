// UI-only transient state. No access to executeAction or mutable lesson state.
export function createRecommendationHighlighter() {
  let ids = [], until = 0, version = null;
  return Object.freeze({
    show(recommendation, now, currentVersion) {
      if (!recommendation || recommendation.stateVersion !== currentVersion) return false;
      ids = [...recommendation.highlightIds]; until = now + 4000; version = currentVersion; return true;
    },
    clear() { ids = []; until = 0; version = null; },
    current(now, currentVersion) {
      if (now >= until || version !== currentVersion) ids = [];
      return [...ids];
    }
  });
}

