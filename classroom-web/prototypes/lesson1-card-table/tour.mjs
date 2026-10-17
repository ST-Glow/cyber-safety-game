const TOUR_STEPS = Object.freeze([
  Object.freeze({
    target: '.mission-header',
    eyebrow: '模块 1 / 5 · 任务栏',
    title: '先看清楚任务状态',
    text: '顶部显示课程目标、当前挑战、剩余时间和已经记录的证据。它帮助你判断现在处于哪一关。'
  }),
  Object.freeze({
    target: '.mission-map',
    eyebrow: '模块 2 / 5 · 中央场景',
    title: '地图是你的网络实验场',
    text: '设备、线路和测试点都在这里。先观察它们之间的关系，再决定要尝试哪一张行动卡。'
  }),
  Object.freeze({
    target: '.feedback-slot',
    eyebrow: '模块 3 / 5 · 反馈区',
    title: '每次尝试都会留下线索',
    text: '这里会告诉你行动造成了什么结果。点错时也不用担心，反馈会说明原因，但不会替你完成判断。'
  }),
  Object.freeze({
    target: '.hand-zone',
    eyebrow: '模块 4 / 5 · 行动手牌',
    title: '五张行动卡都可以尝试',
    text: '先选一张卡，再点击场景中的对象。卡牌不会因为当前不是最佳选择就被锁住，你可以通过结果修正想法。'
  }),
  Object.freeze({
    target: '.action-card[data-card-id="connect-device"]',
    eyebrow: '模块 5 / 5 · 行动卡',
    title: '五张牌分别代表五种行动',
    text: '接入设备、建立连接、配置协议、增设备路、运行测试。牌面文字告诉你用途，真正的答案要靠观察和尝试。'
  })
]);

const clamp = (value, min, max) => Math.max(min, Math.min(max, value));

export function createLesson1Tour(root, callbacks = {}) {
  const overlay = document.createElement('section');
  overlay.className = 'lesson1-tour';
  overlay.hidden = true;
  overlay.setAttribute('role', 'dialog');
  overlay.setAttribute('aria-modal', 'true');
  overlay.setAttribute('aria-label', '第1课操作导览');
  overlay.innerHTML = `
    <div class="tour-spotlight" aria-hidden="true"></div>
    <div class="tour-welcome" data-tour-welcome>
      <span class="tour-kicker">糖果校园 · 数字任务桌</span>
      <h2>先认识你的网络实验台</h2>
      <p>用五张行动卡观察网络怎样从“能用”走向“更可靠”。我们先花一分钟认识界面，再开始挑战。</p>
      <div class="tour-welcome-actions">
        <button type="button" class="tour-primary" data-tour-begin>开始导览</button>
        <button type="button" class="tour-link" data-tour-skip>直接开始</button>
      </div>
    </div>
    <aside class="tour-popover" data-tour-popover hidden>
      <div class="tour-popover-head"><span data-tour-eyebrow></span><strong data-tour-progress></strong></div>
      <h2 data-tour-title></h2>
      <p data-tour-text></p>
      <div class="tour-actions">
        <button type="button" class="tour-link" data-tour-prev>上一步</button>
        <button type="button" class="tour-link" data-tour-skip-step>跳过导览</button>
        <button type="button" class="tour-primary" data-tour-next>下一步</button>
      </div>
    </aside>`;
  root.append(overlay);

  const spotlight = overlay.querySelector('.tour-spotlight');
  const welcome = overlay.querySelector('[data-tour-welcome]');
  const popover = overlay.querySelector('[data-tour-popover]');
  const eyebrow = overlay.querySelector('[data-tour-eyebrow]');
  const progress = overlay.querySelector('[data-tour-progress]');
  const title = overlay.querySelector('[data-tour-title]');
  const body = overlay.querySelector('[data-tour-text]');
  const beginButton = overlay.querySelector('[data-tour-begin]');
  const skipButton = overlay.querySelector('[data-tour-skip]');
  const previousButton = overlay.querySelector('[data-tour-prev]');
  const skipStepButton = overlay.querySelector('[data-tour-skip-step]');
  const nextButton = overlay.querySelector('[data-tour-next]');
  let open = false;
  let welcomeMode = true;
  let stepIndex = 0;

  function positionPopover(targetRect) {
    popover.hidden = false;
    const width = Math.min(390, window.innerWidth - 32);
    popover.style.width = `${width}px`;
    const popoverRect = popover.getBoundingClientRect();
    const below = targetRect.bottom + 18;
    const above = targetRect.top - popoverRect.height - 18;
    const top = below + popoverRect.height <= window.innerHeight - 16
      ? below
      : Math.max(16, above);
    const left = clamp(targetRect.left + targetRect.width / 2 - width / 2, 16, window.innerWidth - width - 16);
    popover.style.left = `${left}px`;
    popover.style.top = `${top}px`;
  }

  function renderStep() {
    const step = TOUR_STEPS[stepIndex];
    const target = root.querySelector(step.target);
    if (!target) return;
    const rect = target.getBoundingClientRect();
    const pad = step.target === '.mission-map' ? 7 : 10;
    spotlight.style.left = `${Math.max(0, rect.left - pad)}px`;
    spotlight.style.top = `${Math.max(0, rect.top - pad)}px`;
    spotlight.style.width = `${Math.min(window.innerWidth, rect.width + pad * 2)}px`;
    spotlight.style.height = `${Math.min(window.innerHeight, rect.height + pad * 2)}px`;
    spotlight.hidden = false;
    welcome.hidden = true;
    popover.hidden = true;
    eyebrow.textContent = step.eyebrow;
    progress.textContent = `${stepIndex + 1} / ${TOUR_STEPS.length}`;
    title.textContent = step.title;
    body.textContent = step.text;
    previousButton.disabled = stepIndex === 0;
    nextButton.textContent = stepIndex === TOUR_STEPS.length - 1 ? '开始探索' : '下一步';
    positionPopover(rect);
    requestAnimationFrame(() => nextButton.focus());
  }

  function renderWelcome() {
    welcome.hidden = false;
    popover.hidden = true;
    spotlight.hidden = true;
    requestAnimationFrame(() => beginButton.focus());
  }

  function render() {
    if (!open) return;
    overlay.hidden = false;
    overlay.dataset.mode = welcomeMode ? 'welcome' : 'step';
    if (welcomeMode) renderWelcome();
    else renderStep();
  }

  function close() {
    if (!open) return;
    open = false;
    overlay.hidden = true;
    callbacks.onClose?.();
  }

  function finish() {
    callbacks.onFinish?.();
    close();
  }

  beginButton.addEventListener('click', () => { welcomeMode = false; stepIndex = 0; render(); });
  skipButton.addEventListener('click', finish);
  skipStepButton.addEventListener('click', finish);
  previousButton.addEventListener('click', () => { stepIndex = Math.max(0, stepIndex - 1); render(); });
  nextButton.addEventListener('click', () => {
    if (stepIndex >= TOUR_STEPS.length - 1) finish();
    else { stepIndex += 1; render(); }
  });
  window.addEventListener('resize', () => { if (open && !welcomeMode) renderStep(); });
  window.addEventListener('keydown', event => {
    if (!open) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    if (event.key === 'Escape') finish();
    else if (!welcomeMode && event.key === 'ArrowLeft' && !previousButton.disabled) { stepIndex -= 1; render(); }
    else if (!welcomeMode && event.key === 'ArrowRight') nextButton.click();
  }, true);

  return Object.freeze({
    open(options = {}) {
      open = true;
      welcomeMode = options.welcome !== false;
      stepIndex = 0;
      callbacks.onOpen?.();
      render();
    },
    close,
    isOpen: () => open,
    refresh: render
  });
}
