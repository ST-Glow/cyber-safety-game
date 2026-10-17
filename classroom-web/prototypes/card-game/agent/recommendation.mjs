export const RECOMMENDATION_TYPES = Object.freeze([
  'operation_help',
  'task_feedback',
  'metacognitive_prompt'
]);

export function createRecommendation({ state, type, level, triggerReason, difficultyType, title, message, rationale = '', suggestedCardId = null, suggestedPacketIds = [], suggestedTargetIds = [], highlightIds = [], now = Date.now() }) {
  if (!RECOMMENDATION_TYPES.includes(type)) throw new Error('未知的小糖建议类型。');
  return {
    id: 'recommendation-' + state.run_id + '-' + state.next_event,
    lessonId: state.meta?.curriculum_lesson_id || state.meta?.task_id,
    type,
    level,
    triggerReason,
    difficultyType,
    difficultyDuration: state.difficultyState?.startedAt === null ? 0 : Math.max(0, now - state.difficultyState.startedAt),
    title,
    message,
    rationale,
    suggestedCardId,
    suggestedPacketIds: [...suggestedPacketIds],
    suggestedTargetIds: [...suggestedTargetIds],
    highlightIds: [...highlightIds],
    stateVersion: state.task_version,
    createdAt: now
  };
}

export function cloneRecommendation(recommendation) {
  return recommendation ? JSON.parse(JSON.stringify(recommendation)) : null;
}
