export function createLessonStateSnapshot(state, config, now = Date.now(), legalTargets = () => []) {
  const result = {
    lessonId: config.meta.curriculum_lesson_id, runId: state.run_id, nextEvent: state.next_event,
    phase: state.phase, elapsedTime: state.elapsed_ms, missionStatus: state.missionStatus,
    agentMode: state.agentMode, taskVersion: state.task_version,
    availableCards: config.cards.filter(c => !c.canUse || c.canUse(state)).map(c => c.id),
    selectedCard: state.selectedCard,
    packets: Object.values(state.packets || {}).map(p => ({
      id: p.id, currentNode: p.area, delivered: p.area === 'receiver',
      arrivalOrder: state.arrivalOrder.indexOf(p.id),
      movableTargets: legalTargets(state, 'forward', 'packet-' + p.id).filter(t => !t.disabledReason).map(t => t.id)
    })),
    nodes: Object.values(state.nodes || {}).map(n => ({ id: n.id, capacity: n.capacity,
      occupancy: Object.values(state.packets || {}).filter(p => p.area === n.id).length,
      congestion: n.status === 'congested',
      available: n.status !== 'congested' && Object.values(state.packets || {}).filter(p => p.area === n.id).length < n.capacity })),
    routes: state.routes, wholeAnnouncementState: state.wholeAnnouncement, reassemblyState: state.reassembly,
    progress: state.progress, recentActions: state.events.slice(-12).map(e => ({type:e.type, detail:e.detail})),
    invalidActionCount: state.mistakes, repeatedStrategyCount: state.invalidActionStreak,
    timeSinceMeaningfulProgress: Math.max(0, now - state.lastMeaningfulProgressAt),
    difficultyState: state.difficultyState, autoInterventionCount: state.autoInterventionCount,
    cooldownRemaining: Math.max(0, state.agentCooldownUntil - now), lastRecommendation: state.lastRecommendation
  };
  return JSON.parse(JSON.stringify(result));
}

