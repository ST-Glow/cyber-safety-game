import { tickAdaptiveTriggered, requestAgentHelp } from './adaptive-triggered-policy.mjs';

// A single mode boundary: both policies receive the identical game and advisor.
export function createAgentTriggerPolicy(mode, {config, detectDifficulty, legalTargets, record}) {
  if (!['adaptive_triggered','user_requested'].includes(mode)) throw Error('Unknown agent mode');
  return Object.freeze({
    tick(state, now) {
      return mode === 'adaptive_triggered' ? tickAdaptiveTriggered(state, config, detectDifficulty, now, record, legalTargets) : null;
    },
    request(state, now) {
      return mode === 'user_requested' ? requestAgentHelp(state, config, now, record, legalTargets) : null;
    }
  });
}

