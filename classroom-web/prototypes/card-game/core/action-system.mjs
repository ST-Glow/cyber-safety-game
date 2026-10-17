import { checkpoint, record, setFeedback } from './mission-state.mjs';

const byId = (cards, id) => cards.find(card => card.id === id) || null;
const normalize = target => typeof target === 'string'
  ? { type: 'object', id: target, label: target }
  : target;

export function createCardActionSystem({ config, legalTargets, applyAction, onInvalid }) {
  function invalid(state, code, detail, reason, now) {
    state.mistakes++;
    setFeedback(state, 'warn', '这里暂时不能走', reason, now);
    record(state, 'action_invalid', { code, ...detail, reason }, now);
    onInvalid?.(state, code, detail, now);
    return { ok: false, code, feedback: state.feedback };
  }
  function getTargets(state, actionId, objectId = null) {
    return (legalTargets(state, actionId, objectId) || []).map(normalize);
  }

  function selectCard(state, cardId, now = Date.now()) {
    if (state.missionStatus === 'success' || state.missionStatus === 'ended') {
      return { ok: false, code: 'mission_closed', feedback: state.feedback };
    }
    const card = byId(config.cards, cardId);
    if (!card) return { ok: false, code: 'unknown_card', feedback: state.feedback };
    if (typeof card.canUse === 'function' && !card.canUse(state)) {
      const text = card.disabledReason?.(state) || '这张行动卡还没有开放。';
      setFeedback(state, 'info', '行动卡暂未开放', text, now);
      onInvalid?.(state, 'card_locked', { card_id: cardId }, now);
      record(state, 'action_invalid', { code: 'card_locked', card_id: cardId }, now);
      return { ok: false, code: 'card_locked', feedback: state.feedback };
    }
    state.selectedCard = cardId;
    state.selectedObject = null;
    state.selectedTarget = null;
    const targets = getTargets(state, cardId, null);
    record(state, 'card_selected', { card_id: cardId, target_count: targets.length }, now);
    return { ok: true, card, targets };
  }

  function selectObject(state, objectId, now = Date.now()) {
    if (!state.selectedCard) {
      setFeedback(state, 'info', '先选择行动卡', '先从底部手牌中选一张行动卡。', now);
      return { ok: false, code: 'card_not_selected', feedback: state.feedback };
    }
    const candidates = getTargets(state, state.selectedCard, null);
    const object = candidates.find(item => item.id === objectId);
    if (!object || object.disabledReason) {
      const reason = object?.disabledReason || '这个对象不是当前行动的合法对象。';
      return invalid(state, 'illegal_object', { card_id: state.selectedCard, object_id: objectId }, reason, now);
    }
    state.selectedObject = objectId;
    state.selectedTarget = null;
    const targets = getTargets(state, state.selectedCard, objectId);
    record(state, 'object_selected', { card_id: state.selectedCard, object_id: objectId, target_count: targets.length }, now);
    return { ok: true, object, targets };
  }

  function selectTarget(state, targetId, now = Date.now()) {
    if (!state.selectedCard) {
      setFeedback(state, 'info', '先选择行动卡', '先从底部手牌中选一张行动卡。', now);
      return { ok: false, code: 'card_not_selected', feedback: state.feedback };
    }
    const available = getTargets(state, state.selectedCard, state.selectedObject);
    const selected = available.find(item => item.id === targetId);
    if (!selected || selected.disabledReason) {
      const reason = selected?.disabledReason || '这个对象不是当前行动的合法目标。';
      return invalid(state, 'illegal_target', { card_id: state.selectedCard, object_id: state.selectedObject, target_id: targetId }, reason, now);
    }
    state.selectedTarget = targetId;
    record(state, 'target_selected', { card_id: state.selectedCard, object_id: state.selectedObject, target_id: targetId }, now);
    return { ok: true, target: selected };
  }

  function validateAction(state) {
    if (!state.selectedCard || !state.selectedTarget) return { ok: false, code: 'selection_incomplete', text: '先选择行动卡和目标。' };
    const target = getTargets(state, state.selectedCard, state.selectedObject).find(item => item.id === state.selectedTarget);
    if (!target || target.disabledReason) return { ok: false, code: 'illegal_target', text: target?.disabledReason || '当前目标不合法。' };
    return { ok: true, target };
  }

  function executeAction(state, now = Date.now()) {
    const validation = validateAction(state);
    if (!validation.ok) {
      setFeedback(state, 'warn', '还差一步', validation.text, now);
      return { ...validation, feedback: state.feedback };
    }
    const before = checkpoint(state);
    const result = applyAction(state, state.selectedCard, state.selectedObject, state.selectedTarget, now, {
      legalTargets: (actionId, objectId = null) => getTargets(state, actionId, objectId),
      setFeedback: (tone, title, text) => setFeedback(state, tone, title, text, now)
    });
    if (!result?.ok) {
      if (result?.committed) {
        state.selectedCard = null;
        state.selectedObject = null;
        state.selectedTarget = null;
        record(state, 'action_executed', { action: before.selectedCard, outcome: result.code }, now);
        return result;
      }
      Object.assign(state, before);
      state.mistakes++;
      setFeedback(state, 'warn', result?.title || '这里还不能使用这张牌', result?.text || '换一个目标试试。', now);
      record(state, 'action_invalid', { code: result?.code || 'invalid_action', card_id: before.selectedCard, target_id: before.selectedTarget }, now);
      return { ok: false, code: result?.code || 'invalid_action', feedback: state.feedback };
    }
    if (result.checkpointed !== true) {
      state.undo.push(before);
      if (state.undo.length > 50) state.undo.shift();
    }
    if (result.versioned !== true) state.task_version++;
    state.selectedCard = null;
    state.selectedObject = null;
    state.selectedTarget = null;
    if (result.phase) state.phase = result.phase;
    if (result.complete) state.missionStatus = 'success';
    record(state, result.eventType || 'action_executed', { action: result.action || before.selectedCard, target_id: before.selectedTarget, ...result.detail }, now);
    return { ...result, ok: true };
  }

  return Object.freeze({ getTargets, selectCard, selectObject, selectTarget, validateAction, executeAction });
}
