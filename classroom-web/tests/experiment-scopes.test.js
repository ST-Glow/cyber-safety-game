import test from 'node:test';
import assert from 'node:assert/strict';
import {movementScope,benchScope} from '../src/levels/scaffold-scope.js';
import {Party,hazards} from '../src/levels/party.js';
import {Puzzle,Repair,Safety} from '../src/levels/workbench.js';
import {createPlayer,step,STEP} from '../src/physics.js';
import {ExperimentScaffold} from '../src/experiment-scaffold.js';

const state=(level,challenge)=>({level,challenge,player:challenge?.player||createPlayer()});
const rng=()=>.31;

test('basic and spinner obstacle scope survive death and identify the same target on a fresh run',()=>{
  const basic=state('ai_training_ground');basic.player.z=-25;
  const gate=movementScope(basic);assert.equal(gate.id,'obstacle:gate_2');
  Object.assign(basic.player,{z:5,respawnSerial:1,lastFailure:{scope_id:gate.id,hazard_id:'basic_gate_2'}});
  assert.equal(movementScope(basic).id,gate.id);
  const retried=state('ai_training_ground');retried.player.z=-25;assert.equal(movementScope(retried).id,gate.id);
  const race=state('spinner_race',new Party('spinner_race'));race.challenge.checkpoints=2;race.player.z=-55;
  const platform=movementScope(race);
  Object.assign(race.player,{z:-41.75,respawnSerial:1,lastFailure:{scope_id:platform.id,hazard_id:null}});
  assert.equal(movementScope(race).id,platform.id);
  assert.equal(platform.id,'obstacle:moving_platforms');
});

test('ordinary backtracking returns to the physical obstacle, while knockback keeps the collision identity',()=>{
  const a=state('ai_training_ground');Object.assign(a.player,{z:-25,x:-4});
  assert.equal(movementScope(a).id,'obstacle:gate_1');
  a.player.z=-40;assert.equal(movementScope(a).id,'obstacle:bridge');
  a.player.z=-25;assert.equal(movementScope(a).id,'obstacle:gate_1');
  Object.assign(a.player,{x:4,knock:.4,lastFailure:{scope_id:'obstacle:gate_1',hazard_id:'basic_gate_1'}});
  assert.equal(movementScope(a).id,'obstacle:gate_1');
  a.player.knock=0;assert.equal(movementScope(a).id,'obstacle:gate_3');
});

function hitBasicGate(index){
  const p=createPlayer();Object.assign(p,{x:-4+index*4,z:-25.5,worldTime:2.7-index*1.2-STEP});
  assert.ok(step(p,{},STEP).includes('obstacle_hit'));
  return p.lastFailure;
}
function hitRacePusher(index){
  const m=new Party('spinner_race');m.countdown=0;m.checkpoints=3;
  const h=hazards('spinner_race',STEP).filter(h=>h.kind==='pusher')[index];
  Object.assign(m.player,{x:h.x,z:h.z});
  const hit=m.tick({},STEP).find(e=>e.name==='obstacle_hit');assert.ok(hit);
  return hit.payload;
}

test('actual collisions identify each of the three basic gates and three race pushers',()=>{
  for(let i=0;i<3;i++){
    const gate=hitBasicGate(i);assert.equal(gate.scope_id,'obstacle:gate_'+(i+1));assert.equal(gate.hazard_id,'basic_gate_'+(i+1));
    const pusher=hitRacePusher(i);assert.equal(pusher.scope_id,'obstacle:pusher_'+(i+1));
    assert.equal(pusher.hazard_id,'spinner_race:pusher:'+(i+1));
  }
});

test('two different gates or pushers do not combine into a reactive two-error invitation',()=>{
  for(const collision of [hitBasicGate,hitRacePusher]){
    const s=new ExperimentScaffold({condition:'reactive',levelId:'scope-test'});
    const fail=(index)=>{const detail=collision(index);s.setScope({id:detail.scope_id,kind:'movement'});s.failure('collision',detail);};
    fail(0);assert.equal(s.pending,null);fail(1);assert.equal(s.pending,null);
    fail(0);assert.ok(s.pending);assert.equal(s.pending.scope_id,collision(0).scope_id);
    assert.equal(s.saved.scopes[collision(0).scope_id].failures,2);
    assert.equal(s.saved.scopes[collision(1).scope_id].failures,1);
  }
});

test('a proactive first failure locks only its concrete gate or pusher, including after returning',()=>{
  for(const collision of [hitBasicGate,hitRacePusher]){
    const s=new ExperimentScaffold({condition:'proactive',levelId:'scope-test'}),first=collision(0),second=collision(1);
    s.setScope({id:first.scope_id,kind:'movement'});s.failure('collision',first);s.tick(16,true);assert.equal(s.pending,null);
    s.setScope({id:second.scope_id,kind:'movement'});s.tick(16,true);assert.ok(s.pending);
    s.setScope({id:first.scope_id,kind:'movement'});s.tick(16,true);assert.equal(s.pending,null);
    assert.equal(s.current.failed,true);
  }
});

test('chip route errors are not keyed by collected count, and spawn recovery keeps the failed route',()=>{
  const a=state('data_chip_hunt',new Party('data_chip_hunt'));
  Object.assign(a.player,{x:-10,z:-3,vx:0,grounded:true,knock:0});
  const route=movementScope(a);assert.equal(route.id,'route:left');
  a.challenge.collected.add(1);a.challenge.collected.add(2);assert.equal(movementScope(a).id,route.id);
  Object.assign(a.player,{x:0,z:10,knock:0});assert.equal(movementScope(a).id,route.id);
  Object.assign(a.player,{x:10,z:-3,vx:1});assert.equal(movementScope(a).id,'route:right');
});

test('bomb wave identity changes at the gameplay boundary and calibrated waves disable proactive waiting',()=>{
  const a=state('signal_bomb_survival',new Party('signal_bomb_survival'));
  a.player.time=19.5;assert.equal(movementScope(a).id,'wave:1');
  a.challenge.calibrated[0]=true;assert.equal(movementScope(a).eligible,false);
  a.player.time=20;assert.equal(movementScope(a).id,'wave:1');
  a.player.time=20+STEP;assert.deepEqual(movementScope(a),{id:'wave:2',kind:'calibration',eligible:true});
});

test('puzzle piece identity survives retry; tray arrangement is activity without an explicit wrong answer',()=>{
  const m=new Puzzle(3,rng),a=state('level_2_puzzle',m),p=m.pieces.at(-1);
  m.pointerDown(p.x+20,p.y+20);const selected=benchScope(a);m.pointerUp(270,190);
  assert.equal(m.errors,0);assert.equal(m.moves,0);assert.equal(m.drain().some(e=>e.name==='digcomp_response_submitted'),false);
  m.pointerDown(p.x+20,p.y+20);assert.equal(benchScope(a).id,selected.id);
  const wrongColumn=(p.col+1)%m.grid;
  m.pointerUp(m.board.x+wrongColumn*p.w+20,m.board.y+p.row*p.h+20);
  assert.equal(m.errors,1);const response=m.drain().find(e=>e.name==='digcomp_response_submitted');assert.equal(response.payload.correct,false);
  assert.equal(benchScope(a,response.payload).id,selected.id);
  const other=state('level_2_puzzle',new Puzzle(4,rng));assert.notEqual(benchScope(other,{task_id:response.payload.task_id}).id,selected.id);
});

test('repair item scope survives wrong strategy and reappearing card; other cards have separate identities',()=>{
  const m=new Repair(rng),a=state('level_3_matching',m);m.tick(STEP);const card=m.active[0];
  const before=benchScope(a,{task_id:card.item.id});m.match('wrong',card);
  const response=m.drain().find(e=>e.name==='digcomp_response_submitted');
  assert.equal(benchScope(a,response.payload).id,before.id);
  card.x=951;const missed=m.tick(STEP).find(e=>e.name==='failure');
  assert.equal(missed.payload.task_id,card.item.id);
  assert.equal(benchScope(a,{task_id:card.item.id}).id,before.id);
  assert.ok(m.remaining.some(item=>item.id===card.item.id));
  assert.notEqual(benchScope(a,{task_id:'another_item'}).id,before.id);
});

test('finished workbench targets are not left eligible while new work waits',()=>{
  const repair=new Repair(rng),a=state('level_3_matching',repair);repair.tick(STEP);repair.tick(2.7);
  assert.equal(repair.active.length,2);const done=repair.active[0],next=repair.active[1];
  repair.match(done.item.id,done);
  assert.equal(benchScope(a).id,'repair:'+next.item.id,'new unresolved card must own the idle timer');
  const puzzle=new Puzzle(3,rng),b=state('level_2_puzzle',puzzle),piece=puzzle.pieces.at(-1);
  puzzle.pointerDown(piece.x+20,piece.y+20);const prior=benchScope(b);
  puzzle.pointerUp(puzzle.board.x+piece.col*piece.w+20,puzzle.board.y+piece.row*piece.h+20);
  assert.equal(piece.locked,true);const after=benchScope(b);
  assert.ok(after.id!==prior.id||after.eligible===false,'completed piece must not retain proactive eligibility');
});

test('safety feedback retains the answered case and original budget; invitation does not change the case timer',()=>{
  const m=new Safety(),a=state('level_4_image_judgment',m),s=new ExperimentScaffold({condition:'proactive',levelId:a.level});
  s.setScope(benchScope(a));m.tick(12);s.tick(12,true);assert.ok(s.pending);assert.equal(m.left,12);
  m.tick(2);s.tick(2,true);assert.equal(m.left,10,'the model timer continues while invitation is merely visible');
  const answered=m.item.id;m.judge(!m.item.answer);const feedback=benchScope(a);
  assert.equal(feedback.id,'case:'+answered);assert.equal(feedback.budget,24);
  assert.notEqual(m.item.id,answered);const before=m.time;m.tick(15);assert.equal(m.time,before);
  m.action('continue-case');assert.notEqual(benchScope(a).id,feedback.id);
  while(m.index<3){m.judge(m.item.answer);m.action('continue-case');}
  assert.equal(benchScope(a).budget,18);
  while(m.index<7){m.judge(m.item.answer);m.action('continue-case');}
  assert.equal(benchScope(a).budget,15);
});
