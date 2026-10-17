import { advise } from './agent-advisor.mjs';
import { createLessonStateSnapshot } from './lesson-state-adapter.mjs';
export const ADAPTIVE_DIFFICULTY_MS = 20000;
export const ADAPTIVE_COOLDOWN_MS = 30000;
export const ADAPTIVE_MAX_INTERVENTIONS = 3;
const blank = now => ({active:false,type:null,startedAt:null,lastUpdatedAt:now,evidence:[],recommendationTriggered:false,adviceLevel:1});
export function ensureAgentState(state, mode = 'adaptive_triggered') {
  state.agentMode = mode;
  state.difficultyState ||= blank(null);
  state.autoInterventionCount ??= 0; state.agentCooldownUntil ??= 0;
  state.lastRecommendation ??= null; state.recommendationViews ||= {};
}
export function clearDifficulty(state, now, reason, record) {
  const previous = state.difficultyState;
  if (!previous?.active) return false;
  record(state,'difficulty_cleared',{difficulty_type:previous.type,difficulty_duration:now-previous.startedAt,reason},now);
  state.difficultyState = blank(now);
  return true;
}
export function markMeaningfulProgress(state, kind, detail, now, record) {
  state.lastMeaningfulProgressAt = now;
  state.meaningfulProgressSeq = (state.meaningfulProgressSeq || 0) + 1;
  state.invalidActionStreak = 0; state.invalidHistory = [];
  record(state,'meaningful_progress',{kind,...detail},now);
  clearDifficulty(state,now,kind,record);
}
function generate(state, config, now, record, legalTargets, trigger) {
  const recommendation = advise(createLessonStateSnapshot(state,config,now,legalTargets),null,now);
  recommendation.triggerReason = trigger;
  state.lastRecommendation = recommendation;
  state.lastRecommendationProgressSeq = state.meaningfulProgressSeq;
  record(state,'agent_triggered',{trigger},now);
  record(state,'recommendation_generated',{recommendation_id:recommendation.id,level:recommendation.level},now);
  return recommendation;
}
export function tickAdaptiveTriggered(state, config, detect, now, record, legalTargets) {
  ensureAgentState(state,state.agentMode);
  if (state.agentMode !== 'adaptive_triggered' || state.missionStatus === 'success' || state.ended_at !== null) return null;
  if (state.agentCooldownUntil && now >= state.agentCooldownUntil) {
    state.agentCooldownUntil = 0; record(state,'agent_cooldown_ended',{},now);
  }
  const detected = detect(state,now);
  if (!detected) { clearDifficulty(state,now,'condition_ended',record); return null; }
  let d = state.difficultyState;
  if (!d.active || d.type !== detected.type) {
    if (d.active) clearDifficulty(state,now,'difficulty_changed',record);
    d = state.difficultyState = {...blank(now),active:true,type:detected.type,startedAt:now,evidence:detected.evidence};
    record(state,'difficulty_detected',{difficulty_type:d.type,evidence:d.evidence},now);
  }
  d.lastUpdatedAt = now;
  if (JSON.stringify(d.evidence) !== JSON.stringify(detected.evidence)) {
    d.evidence = detected.evidence; record(state,'difficulty_updated',{evidence:d.evidence},now);
  }
  const previous = state.lastRecommendation;
  // Re-arm only after the student viewed the previous support and cooldown ended.
  if (d.recommendationTriggered && !state.agentCooldownUntil && previous &&
      state.recommendationViews[previous.id] && previous.level < 3) {
    d.recommendationTriggered = false; d.startedAt = now;
    d.adviceLevel = previous.level + 1;
    record(state,'difficulty_updated',{reason:'viewed_support_still_unresolved',level:d.adviceLevel},now);
  }
  if (now-d.startedAt < ADAPTIVE_DIFFICULTY_MS || d.recommendationTriggered ||
      state.agentCooldownUntil || state.autoInterventionCount >= ADAPTIVE_MAX_INTERVENTIONS) return null;
  if (previous && state.recommendationViews[previous.id] && state.lastRecommendationProgressSeq === state.meaningfulProgressSeq) {
    d.adviceLevel = Math.min(3,previous.level+1);
  }
  d.recommendationTriggered = true;
  record(state,'difficulty_20s_reached',{difficulty_duration:now-d.startedAt},now);
  const recommendation = generate(state,config,now,record,legalTargets,'adaptive_triggered');
  state.autoInterventionCount++;
  state.agentCooldownUntil = now + ADAPTIVE_COOLDOWN_MS;
  record(state,'agent_cooldown_started',{until:state.agentCooldownUntil},now);
  return recommendation;
}
export function requestAgentHelp(state,config,now,record,legalTargets) {
  ensureAgentState(state,state.agentMode);
  if (state.agentMode !== 'user_requested') return null;
  return generate(state,config,now,record,legalTargets,'user_requested');
}

