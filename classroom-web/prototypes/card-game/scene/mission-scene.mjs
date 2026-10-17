import { renderSceneObject } from './object-renderer.mjs';
import { renderRoutes } from './route-renderer.mjs';

export function createMissionScene(root, config, callbacks) {
  root.innerHTML = '<div class="mission-map"><div class="map-title"><span class="map-sticker">校园任务地图</span><strong></strong><small></small></div><div class="map-stage"></div></div>';
  const map = root.querySelector('.mission-map');
  const stage = root.querySelector('.map-stage');
  const title = root.querySelector('.map-title strong');
  const subtitle = root.querySelector('.map-title small');

  function render(state, actionSystem, ui = {}) {
    title.textContent = state.phase === 'SUCCESS' ? '公告已经恢复' : config.missionTitle;
    subtitle.textContent = state.phase === 'WHOLE_DATA_BLOCKED' ? '先试着把完整公告送出去' : state.phase === 'PACKETIZATION' ? '公告太大，先把它拆成小包' : state.phase === 'CONGESTION' ? 'A 站拥堵：转发时观察其他站点' : state.phase === 'REASSEMBLY' ? '都到了，但要按编号重组' : '让数据包经过校园节点';
    const rootTargets = new Set((state.selectedCard ? actionSystem.getTargets(state, state.selectedCard, state.selectedObject) : []).map(item => item.id));
    for (const id of ui.highlightIds || []) rootTargets.add(id);
    const objects = config.sceneObjects;
    stage.innerHTML = '';
    stage.append(renderRoutes(config.routes, state));
    for (const object of objects) {
      stage.append(renderSceneObject(object, state, rootTargets, state.selectedObject, callbacks.onObject));
    }
    if (state.selectedCard) {
      const hint = document.createElement('div');
      hint.className = 'selection-hint';
      hint.textContent = state.selectedObject ? '再选择一个高亮目标' : '选择高亮的数据包或目的地';
      stage.append(hint);
    }
    map.dataset.stage = String(state.tutorialStage);
  }

  return { root, map, render };
}
