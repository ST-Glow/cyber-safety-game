export function renderHelpEntry(root, state, onHelp) {
  root.innerHTML = '<span class="helper-avatar" aria-hidden="true">糖</span><div><strong>需要一点提示？</strong><small>帮助不会替你完成任务</small></div><button type="button" aria-label="获取操作提示">提示</button>';
  root.querySelector('button').addEventListener('click', () => onHelp('operation_help'));
}
