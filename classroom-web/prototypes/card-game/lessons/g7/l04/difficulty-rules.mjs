export const GRACE_MS = 5000;
export const STALL_MS = 20000;

// A detection threshold is separate from the subsequent continuous 20 s interval.
export function detectDifficulty(state, now) {
  if (state.missionStatus === 'success' || state.ended_at !== null) return null;
  const phaseAge = now - (state.phaseStartedAt ?? now);
  const progressAge = now - (state.lastMeaningfulProgressAt ?? now);
  const recent = (state.invalidHistory || []).filter(e => e.progressSeq === state.meaningfulProgressSeq);
  if (recent.filter(e => ['card_locked', 'illegal_object', 'card_not_selected'].includes(e.code)).length >= 2) {
    return { type: 'operation_confusion', evidence: recent.slice(-3) };
  }
  if (recent.length >= 3 && recent.slice(-3).every(e => (e.target_id || e.targetId) === 'node-a')) {
    return { type: 'repeated_failed_strategy', evidence: recent.slice(-3) };
  }
  if (recent.length >= 2 && recent.at(-1).code === recent.at(-2).code) {
    return { type: 'repeated_invalid_action', evidence: recent.slice(-2) };
  }
  if (phaseAge < GRACE_MS || progressAge < STALL_MS) return null;
  if (['ready','sorting'].includes(state.reassembly?.status)) {
    return { type: 'stalled_reassembly', evidence: ['no_improved_order_for_20s'] };
  }
  // Every nonterminal L04 board has a way forward; no mouse-idle heuristic.
  if (!state.completed) return { type: 'stalled_progress', evidence: ['legal_progress_exists', 'no_meaningful_progress_for_20s'] };
  return null;
}

