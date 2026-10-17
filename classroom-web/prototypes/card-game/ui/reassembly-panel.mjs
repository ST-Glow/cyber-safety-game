export function renderReassemblyPanel(root,state,onOrder) {
  root.hidden = state.reassembly?.status !== 'sorting';
  if(root.hidden) { root.replaceChildren(); return; }
  const selected=state.reassembly.selectedOrder;
  root.innerHTML='<div class="reassembly-card"><strong>按你的判断排列数据包</strong><div class="sorting-slots"></div><div class="reassembly-order"></div><div class="reassembly-actions"><button data-reset>重来</button><button data-check>检查顺序</button></div></div>';
  const slots=root.querySelector('.sorting-slots');
  for(let i=0;i<4;i++) {
    const slot=document.createElement('span'); slot.textContent=selected[i] || '空位'; slots.append(slot);
  }
  for(const id of state.arrivalOrder) {
    const b=document.createElement('button'); b.type='button'; b.dataset.sortId=id;
    b.className='reassembly-chip'+(selected.includes(id)?' chosen':'');
    b.textContent=id+' · '+state.packets[id].text;
    b.disabled=selected.includes(id);
    b.onclick=()=>onOrder([...selected,id]);
    root.querySelector('.reassembly-order').append(b);
  }
  root.querySelector('[data-reset]').onclick=()=>onOrder([]);
  root.querySelector('[data-check]').onclick=()=>onOrder(selected,{check:true});
}

