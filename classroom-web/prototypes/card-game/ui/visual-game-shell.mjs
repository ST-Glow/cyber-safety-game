import { renderCardHand } from './card-hand.mjs';
import { renderMissionFeedback } from './mission-feedback.mjs';
import { renderMissionHeader, updateMissionClock } from './mission-header.mjs';
import { renderAgentSidebar } from './agent-sidebar.mjs';

// A visual-only shell shared by lessons that use the campus board and card table.
// The original createGameShell remains untouched for lesson 4's packet workflow.
export function createVisualGameShell(root, config, callbacks, options = {}) {
  root.innerHTML = '<div class="campus-shell"><header class="mission-header"></header><main class="mission-main"><section class="scene-slot" aria-label="任务场景"></section></main><section class="feedback-slot" aria-live="polite"></section><section class="hand-zone"><div class="hand-heading"><span>行动手牌</span><strong>选牌 → 点击场景对象 → 看反馈</strong></div><div class="card-hand"></div></section><section class="agent-sidebar-slot"></section><section class="success-layer" hidden></section></div>';
  const q = selector => root.querySelector(selector);
  const header = q('.mission-header');
  const sceneSlot = q('.scene-slot');
  const hand = q('.card-hand');
  const agentSidebar = q('.agent-sidebar-slot');
  const success = q('.success-layer');
  const toolHandlers = {
    menu: callbacks.onMenu,
    undo: callbacks.onUndo,
    save: callbacks.onSave,
    load: callbacks.onLoad,
    export: callbacks.onExport,
    help: () => callbacks.onHelp?.('operation_help'),
    tour: callbacks.onTour,
    restart: callbacks.onRestart,
    end: callbacks.onEnd
  };

  function render(state) {
    const ui = callbacks.getAgentUi?.() || {};
    const viewState = options.prepareState ? options.prepareState(state) : state;
    const challengeIndex = Number(viewState.data?.challengeIndex ?? 0);
    const shell = q('.campus-shell');
    shell.dataset.challenge = String(challengeIndex);
    shell.dataset.guidance = challengeIndex === 0 ? 'tutorial' : 'challenge';
    q('.hand-heading strong').textContent = challengeIndex === 0
      ? '新手练习：选牌 → 点击目标 → 看反馈'
      : '观察场景 → 任选行动卡 → 验证结果';
    renderMissionHeader(header, config, viewState, ui);
    for (const button of header.querySelectorAll('[data-tool]')) {
      const handler = toolHandlers[button.dataset.tool];
      if (handler) button.onclick = handler;
    }
    renderCardHand(hand, config, viewState, callbacks.onSelectCard, {
      ...ui,
      selectedCard: options.selectedCard?.(state),
      getCardState: options.getCardState
    });
    renderMissionFeedback(q('.feedback-slot'), viewState);
    renderAgentSidebar(agentSidebar, viewState, ui, {
      onOpen: callbacks.onAgentOpen,
      onClose: callbacks.onAgentClose,
      onHighlight: callbacks.onAgentHighlight,
      onWhy: callbacks.onAgentWhy
    });
    if (typeof options.renderSuccess === 'function') {
      options.renderSuccess(success, state, ui, callbacks);
    } else {
      success.hidden = true;
    }
  }

  return {
    root,
    sceneSlot,
    hand,
    agentSidebar,
    render,
    updateClock: state => updateMissionClock(header, config, options.prepareState ? options.prepareState(state) : state)
  };
}
