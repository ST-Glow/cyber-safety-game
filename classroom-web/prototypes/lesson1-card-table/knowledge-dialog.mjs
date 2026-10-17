import { KNOWLEDGE_CHECKPOINTS } from './adapters/lesson1-knowledge.mjs';

export function createKnowledgeDialog(root, callbacks) {
  const dialog = document.createElement('dialog');
  dialog.className = 'knowledge-dialog';
  dialog.setAttribute('aria-labelledby', 'knowledge-title');
  dialog.setAttribute('aria-describedby', 'knowledge-instructions');
  dialog.innerHTML = `
    <div class="knowledge-heading"><span>发现整理站</span><strong data-knowledge-stage></strong></div>
    <h2 id="knowledge-title"></h2>
    <p id="knowledge-instructions">把左侧金色概念卡拖到右侧对应的绿色解释卡上；触屏或键盘也可以依次点击两张卡。</p>
    <div class="knowledge-meta"><span>主线计时已暂停</span><strong data-knowledge-progress></strong></div>
    <div class="knowledge-match-board" aria-label="知识匹配卡牌">
      <section class="knowledge-column knowledge-concept-column" aria-label="概念卡区域">
        <div class="knowledge-column-heading"><strong>概念卡</strong><span>拖动出发</span></div>
        <div class="knowledge-cards knowledge-concept-cards"></div>
      </section>
      <div class="knowledge-drag-rail" aria-hidden="true"><span>拖到<br>这里</span><b>→</b></div>
      <section class="knowledge-column knowledge-explanation-column" aria-label="解释卡区域">
        <div class="knowledge-column-heading"><strong>解释卡</strong><span>放到这里</span></div>
        <div class="knowledge-cards knowledge-explanation-cards"></div>
      </section>
    </div>
    <p class="knowledge-feedback" role="status" aria-live="polite"></p>
    <p class="knowledge-save-status" role="status"></p>
    <div class="knowledge-actions">
      <button type="button" class="tour-link" data-knowledge-skip>跳过本次匹配</button>
      <button type="button" class="tour-primary" data-knowledge-continue>继续探索</button>
    </div>`;
  root.append(dialog);
  const conceptCards = dialog.querySelector('.knowledge-concept-cards');
  const explanationCards = dialog.querySelector('.knowledge-explanation-cards');
  const feedback = dialog.querySelector('.knowledge-feedback');
  let currentKey = null;
  let currentKnowledge = null;
  let animationTimer = null;
  let autoContinueTimer = null;
  let autoContinueCountdown = null;
  let autoContinueKey = null;

  function message(text, tone = 'info') {
    feedback.textContent = text;
    feedback.dataset.tone = tone;
  }

  function cardsFor(kind) {
    return kind === 'concept' ? conceptCards : explanationCards;
  }

  function clearDropTargets() {
    explanationCards.querySelectorAll('.drop-target').forEach(node => node.classList.remove('drop-target'));
  }

  function clearAutoContinue() {
    clearTimeout(autoContinueTimer);
    clearInterval(autoContinueCountdown);
    autoContinueTimer = null;
    autoContinueCountdown = null;
    autoContinueKey = null;
  }

  function continueExploring(reason) {
    clearAutoContinue();
    callbacks.onContinue(reason);
  }

  function scheduleAutoContinue(key) {
    if (autoContinueKey === key) return;
    clearAutoContinue();
    autoContinueKey = key;
    let seconds = 3;
    const update = () => {
      if (autoContinueKey !== key || currentKey !== key || currentKnowledge?.checkpoints[currentKnowledge.current]?.status !== 'completed') {
        clearAutoContinue();
        return;
      }
      message(`配对完成，${seconds}秒后自动继续探索；也可以现在点击按钮。`, 'success');
    };
    update();
    autoContinueCountdown = setInterval(() => {
      seconds -= 1;
      if (seconds > 0) update();
    }, 1000);
    autoContinueTimer = setTimeout(() => {
      if (autoContinueKey === key && currentKey === key && dialog.open
        && currentKnowledge?.checkpoints[currentKnowledge.current]?.status === 'completed') {
        continueExploring('auto');
      } else clearAutoContinue();
    }, 3000);
  }

  function pairWithExplanation(id, button) {
    if (!currentKnowledge?.checkpoints[currentKnowledge.current]?.selected) {
      message('先拖动或点击一张金色概念卡，再选择对应的绿色解释卡。', 'error');
      return;
    }
    const result = callbacks.onPair(id);
    if (!result?.ok) return;
    // onPair renders synchronously, including the completion countdown. Keep
    // that message instead of replacing it with the ordinary pair feedback.
    if (currentKnowledge.checkpoints[currentKnowledge.current]?.status !== 'completed') {
      message(result.text, result.correct ? 'success' : 'error');
    }
    if (!result.correct) {
      clearTimeout(animationTimer);
      dialog.querySelectorAll('.mismatch').forEach(node => node.classList.remove('mismatch'));
      const wrongCards = [
        conceptCards.querySelector(`[data-knowledge-card="concept:${result.conceptId}"]`),
        button
      ].filter(Boolean);
      wrongCards.forEach(node => {
        node.getBoundingClientRect();
        node.classList.add('mismatch');
      });
      animationTimer = setTimeout(() => wrongCards.forEach(node => node.classList.remove('mismatch')), 420);
    }
    clearDropTargets();
  }

  function createCard(kind, id, pair) {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = `knowledge-card knowledge-${kind}`;
    button.dataset.knowledgeCard = `${kind}:${id}`;
    button.innerHTML = '<span class="knowledge-card-grip" aria-hidden="true">⋮⋮</span><span class="knowledge-card-kind"></span><strong></strong><span class="knowledge-card-status"></span>';
    button.querySelector('.knowledge-card-kind').textContent = kind === 'concept' ? '概念卡' : '解释卡';
    button.querySelector('strong').textContent = pair[kind];

    if (kind === 'concept') {
      button.draggable = true;
      button.addEventListener('click', () => {
        callbacks.onSelect(id);
        message('已拿起“' + pair.concept + '”，把它拖到右侧对应的解释卡。');
      });
      button.addEventListener('dragstart', event => {
        if (currentKnowledge.checkpoints[currentKnowledge.current].selected !== id) callbacks.onSelect(id);
        event.dataTransfer.effectAllowed = 'move';
        event.dataTransfer.setData('text/knowledge-concept', id);
        event.dataTransfer.setData('text/plain', id);
        button.classList.add('dragging');
        message('正在拖动“' + pair.concept + '”，松开放到对应解释卡。');
      });
      button.addEventListener('dragend', () => {
        button.classList.remove('dragging');
        clearDropTargets();
      });
    } else {
      button.addEventListener('click', () => pairWithExplanation(id, button));
      button.addEventListener('dragenter', event => {
        event.preventDefault();
        if (!button.disabled) button.classList.add('drop-target');
      });
      button.addEventListener('dragover', event => {
        event.preventDefault();
        event.dataTransfer.dropEffect = 'move';
        if (!button.disabled) button.classList.add('drop-target');
      });
      button.addEventListener('dragleave', event => {
        if (!button.contains(event.relatedTarget)) button.classList.remove('drop-target');
      });
      button.addEventListener('drop', event => {
        event.preventDefault();
        pairWithExplanation(id, button);
      });
    }
    return button;
  }

  function render(knowledge, runId, saveMessage = '') {
    currentKnowledge = knowledge;
    if (knowledge.current === null) {
      if (dialog.open) dialog.close();
      currentKey = null;
      clearTimeout(animationTimer);
      clearAutoContinue();
      return;
    }
    const index = knowledge.current;
    const checkpoint = knowledge.checkpoints[index];
    const definition = KNOWLEDGE_CHECKPOINTS[index];
    const key = `${runId}:${index}:${checkpoint.order.join(',')}`;
    if (key !== currentKey) {
      currentKey = key;
      conceptCards.replaceChildren();
      explanationCards.replaceChildren();
      dialog.querySelector('#knowledge-title').textContent = definition.title;
      dialog.querySelector('[data-knowledge-stage]').textContent = `第 ${index + 1} / 3 站`;
      for (const cardId of checkpoint.order) {
        const [kind, id] = cardId.split(':');
        const pair = definition.pairs.find(item => item.id === id);
        cardsFor(kind).append(createCard(kind, id, pair));
      }
      message(checkpoint.status === 'completed' ? '两组知识已经整理好，可以继续探索。' : '拖动一张概念卡到你认为对应的解释卡上。');
    }
    for (const button of dialog.querySelectorAll('.knowledge-card')) {
      const [kind, id] = button.dataset.knowledgeCard.split(':');
      const matched = checkpoint.matched.includes(id);
      const selected = kind === 'concept' && checkpoint.selected === id;
      button.disabled = matched;
      button.classList.toggle('matched', matched);
      button.classList.toggle('selected', selected);
      if (kind === 'concept') button.setAttribute('aria-pressed', String(selected));
      button.querySelector('.knowledge-card-status').textContent = matched ? '✓ 已配对' : selected ? '已拿起 · 拖到右侧' : kind === 'concept' ? '拖动或点击选择' : '接收概念卡';
    }
    dialog.querySelector('[data-knowledge-progress]').textContent = `已配对 ${checkpoint.matched.length} / 2 · 尝试 ${checkpoint.attempts.length} 次`;
    dialog.querySelector('.knowledge-save-status').textContent = saveMessage;
    dialog.querySelector('[data-knowledge-skip]').hidden = checkpoint.status === 'completed';
    if (checkpoint.status === 'completed') scheduleAutoContinue(key);
    else if (autoContinueKey !== null) clearAutoContinue();
    if (!dialog.open) {
      dialog.showModal();
      (conceptCards.querySelector('.knowledge-concept:not(:disabled)') || dialog.querySelector('[data-knowledge-continue]')).focus();
    } else if (checkpoint.status === 'completed' && document.activeElement?.disabled) {
      dialog.querySelector('[data-knowledge-continue]').focus();
    }
  }
  dialog.querySelector('[data-knowledge-skip]').onclick = () => continueExploring('skip');
  dialog.querySelector('[data-knowledge-continue]').onclick = () => continueExploring('continue');
  dialog.addEventListener('cancel', event => { event.preventDefault(); continueExploring('escape'); });
  return { render, isOpen: () => dialog.open };
}
