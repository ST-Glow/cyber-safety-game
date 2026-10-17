import { renderCardHand } from './card-hand.mjs';
import { renderMissionFeedback } from './mission-feedback.mjs';
import { renderMissionHeader, updateMissionClock } from './mission-header.mjs';
import { renderReassemblyPanel } from './reassembly-panel.mjs';
import { renderAgentSidebar } from './agent-sidebar.mjs';

export function createGameShell(root,config,callbacks) {
  root.innerHTML='<div class="campus-shell"><header class="mission-header"></header><main class="mission-main"><section class="scene-slot" aria-label="任务地图"></section></main><section class="feedback-slot" aria-live="polite"></section><section class="hand-zone"><div class="hand-heading"><span>行动手牌</span><strong>选牌 → 选对象 → 选下一站</strong></div><div class="card-hand"></div></section><section class="reassembly-slot" hidden></section><section class="agent-sidebar-slot"></section><section class="success-layer" hidden></section></div>';
  const q=s=>root.querySelector(s), header=q('.mission-header'), sceneSlot=q('.scene-slot'), hand=q('.card-hand'), reassembly=q('.reassembly-slot'), agentSidebar=q('.agent-sidebar-slot'), success=q('.success-layer');
  const toolHandlers={menu:callbacks.onMenu,undo:callbacks.onUndo,save:callbacks.onSave,load:callbacks.onLoad,export:callbacks.onExport,help:()=>callbacks.onHelp('operation_help'),restart:callbacks.onRestart,end:callbacks.onEnd};
  function render(state) {
    const ui=callbacks.getAgentUi();
    renderMissionHeader(header,config,state,ui);
    for(const b of header.querySelectorAll('[data-tool]')) b.onclick=toolHandlers[b.dataset.tool];
    renderCardHand(hand,config,state,callbacks.onSelectCard,ui);
    renderMissionFeedback(q('.feedback-slot'),state);
    renderReassemblyPanel(reassembly,state,callbacks.onReassemblyOrder);
    renderAgentSidebar(agentSidebar,state,ui,{onOpen:callbacks.onAgentOpen,onClose:callbacks.onAgentClose,onHighlight:callbacks.onAgentHighlight,onWhy:callbacks.onAgentWhy});
    const won=state.missionStatus==='success', ended=state.ended_at!==null;
    success.hidden=!(ended || won && !ui.successDismissed);
    if(!success.hidden) {
      success.innerHTML='<div class="success-card"><span class="success-stamp"></span><h2></h2><strong></strong><small></small><div class="success-lessons"></div><button class="restart-button"></button></div>';
      success.querySelector('.success-stamp').textContent=won?'✓ 已送达':'本局已结束';
      success.querySelector('h2').textContent=won?'公告屏亮起来了':'这次先到这里';
      success.querySelector('strong').textContent=won?state.reassembly.draft.message:'已送达 '+state.arrivalOrder.length+'/4';
      success.querySelector('small').textContent='到达顺序：'+(state.arrivalOrder.join(' → ')||'尚无');
      success.querySelector('.success-lessons').textContent=won?'大数据可拆包 · 小包可分路 · 接收后按编号重组':'进度和过程记录已保留在本机。';
      const b=success.querySelector('button'); b.textContent=won?'完成任务':'重新开始'; b.onclick=won?callbacks.onFinish:callbacks.onRestart;
    }
  }
  return {root,sceneSlot,hand,reassembly,agentSidebar,render,updateClock:state=>updateMissionClock(header,config,state)};
}

