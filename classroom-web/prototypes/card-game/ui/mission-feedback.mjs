export function renderMissionFeedback(root, state) {
  root.dataset.tone = state.feedback?.tone || 'info';
  root.innerHTML = '<span class="feedback-dot" aria-hidden="true"></span><div><strong></strong><p></p></div>';
  root.querySelector('strong').textContent = state.feedback?.title || '';
  root.querySelector('p').textContent = state.feedback?.text || '';
}
