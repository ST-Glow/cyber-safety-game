export function renderMissionHeader(root, config, state, ui = {}) {
  const tourButton = config.showTour ? '<button data-tool="tour">重新查看导览</button>' : '';
  root.innerHTML = '<div class="header-copy"><span class="mission-kicker"></span><h1></h1><p></p></div><div class="mission-status"></div><button type="button" data-tool="menu" class="menu-button" aria-label="牌桌菜单" aria-expanded="false">菜单</button><div class="pause-menu" hidden><button data-tool="undo">撤销上一步</button><button data-tool="load">恢复本机进度</button><button data-tool="save">保存备份</button><button data-tool="export">导出过程记录</button><button data-tool="help">操作帮助</button>' + tourButton + '<button data-tool="restart">重新开始</button><button data-tool="end">结束本局</button></div>';
  root.querySelector('.mission-kicker').textContent = config.title;
  root.querySelector('h1').textContent = config.missionTitle;
  root.querySelector('p').textContent = config.objective;
  root.querySelector('.pause-menu').hidden = !ui.menuOpen;
  root.querySelector('[data-tool="menu"]').setAttribute('aria-expanded', String(Boolean(ui.menuOpen)));
  updateMissionClock(root,config,state);
}
export function updateMissionClock(root,config,state) {
  const remaining = Math.max(0,Math.ceil((config.timeLimitMs - state.elapsed_ms)/1000));
  const progressLabel = config.progressLabel || '到达';
  const progressValue = config.progressTotal === null
    ? String(state.progress.arrived) + (config.progressSuffix || '')
    : String(state.progress.arrived) + '/' + String(config.progressTotal ?? 4);
  root.querySelector('.mission-status').innerHTML = '<span class="status-label">' + (remaining ? '剩余时间' : '可以继续收尾') + '</span><strong>' +
    Math.floor(remaining/60) + ':' + String(remaining%60).padStart(2,'0') + '</strong><span class="status-progress">' + progressLabel + ' ' + progressValue + '</span>';
}

