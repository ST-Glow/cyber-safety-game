export function renderAgentSidebar(root,state,ui,callbacks) {
  const rec=state.lastRecommendation;
  const fresh=rec && rec.stateVersion===state.task_version;
  root.innerHTML='<button class="agent-tab" data-agent-tab aria-label="打开小糖"><span>糖</span><strong>小糖</strong></button><button class="agent-bubble" hidden>这里好像卡住了，我有个思路。</button><aside class="agent-drawer" hidden aria-label="小糖建议"></aside>';
  const tab=root.querySelector('.agent-tab'), bubble=root.querySelector('.agent-bubble'), drawer=root.querySelector('.agent-drawer');
  tab.classList.toggle('has-recommendation',Boolean(fresh && !state.recommendationViews?.[rec.id]));
  tab.onclick=callbacks.onOpen; bubble.onclick=callbacks.onOpen;
  bubble.hidden=!ui.bubble || !fresh || ui.open;
  drawer.hidden=!ui.open;
  if(!ui.open) return;
  drawer.innerHTML='<div class="agent-drawer-head"><span class="agent-avatar">糖</span><div><strong>小糖</strong><small>你的数字牌搭子</small></div><button data-close aria-label="收起小糖">×</button></div><div class="agent-observation"><small>我看到的情况</small><strong></strong><p></p></div><div class="agent-actions"><button data-highlight>在棋盘上标出来</button><button data-try>我自己再试试</button><button data-why>为什么？</button></div><p class="agent-rationale" hidden></p>';
  drawer.querySelector('[data-close]').onclick=callbacks.onClose;
  drawer.querySelector('[data-try]').onclick=callbacks.onClose;
  drawer.querySelector('.agent-observation strong').textContent=fresh?rec.title:'我在旁边陪你';
  drawer.querySelector('.agent-observation p').textContent=fresh?rec.message:rec?'牌桌已经变化，继续观察当前状态。':'先试试手中的牌。有新思路时，我会轻轻提醒你。';
  drawer.querySelector('[data-highlight]').disabled=!fresh;
  drawer.querySelector('[data-why]').disabled=!rec;
  drawer.querySelector('[data-highlight]').onclick=()=>callbacks.onHighlight(rec);
  drawer.querySelector('[data-why]').onclick=()=>callbacks.onWhy(rec);
  const rationale=drawer.querySelector('.agent-rationale');
  rationale.hidden=!ui.why;
  rationale.textContent=rec?.rationale || '';
}

