export function renderCardHand(root, config, state, onSelectCard, ui = {}) {
  root.innerHTML = '';
  root.dataset.stage = String(state.tutorialStage);
  root.dataset.cardCount = String(config.cards.length);
  for (const card of config.cards) {
    const button = document.createElement('button');
    const cardState = typeof ui.getCardState === 'function'
      ? ui.getCardState(card, state)
      : null;
    const unlocked = cardState?.unlocked ?? (typeof card.canUse !== 'function' || card.canUse(state));
    const selectedCard = ui.selectedCard ?? state.selectedCard;
    button.type = 'button';
    button.className = 'action-card' + (selectedCard === card.id ? ' selected' : '') + (!unlocked ? ' locked' : '') + ((ui.highlightIds || []).includes(card.id) ? ' agent-highlight' : '');
    button.dataset.cardId = card.id;
    button.disabled = !unlocked || state.missionStatus === 'success' || state.missionStatus === 'ended' || state.completed;
    const icon = card.iconSprite
      ? '<span class="card-icon sprite-icon" data-icon-index="' + Number(card.iconIndex || 0) + '" aria-hidden="true"></span>'
      : '<span class="card-icon">' + (card.icon || '') + '</span>';
    button.innerHTML = icon + '<span class="card-copy"><strong></strong><small></small><em></em></span>';
    button.querySelector('strong').textContent = card.label;
    button.querySelector('small').textContent = card.description;
    button.querySelector('em').textContent = unlocked ? card.rule : (cardState?.reason || card.disabledReason?.(state) || '稍后开放');
    button.addEventListener('click', () => onSelectCard(card.id));
    root.append(button);
  }
}
