import test from 'node:test';
import assert from 'node:assert/strict';
import {ExperimentScaffold, RULES, POLICY} from '../src/experiment-scaffold.js';

const target=(id='obstacle:spinner',kind='movement',extra={})=>({id,kind,...extra});
function setup(condition='proactive',saved={}) {
  const events=[],journal=[];
  const s=new ExperimentScaffold({condition,lessonId:'lesson-a',levelId:'ai_training_ground',saved,
    state:()=>({current_area:'training'}),emit:(name,data)=>events.push({name,data}),persist:e=>journal.push(e)});
  s.setScope(target());
  return {s,events,journal};
}
function advance(s,seconds,{safe=true,active=true,step=1/60}={}) {
  const ticks=Math.floor(seconds/step);
  for(let i=0;i<ticks;i++)s.tick(step,safe,active);
  const remainder=seconds-ticks*step;if(remainder>1e-10)s.tick(remainder,safe,active);
}
const shown=f=>f.events.filter(e=>e.name==='scaffold_invitation_shown');

test('proactive rejection persists through refresh and scope return until effective progress',()=>{
  const f=setup();advance(f.s,15.1);f.s.decide('rejected');advance(f.s,40);assert.equal(f.s.pending,null);
  f.s.setScope(target('obstacle:other'));f.s.setScope(target());advance(f.s,40);assert.equal(f.s.pending,null);
  const restored=setup('proactive',{scopes:f.s.saved.scopes,shown:f.s.count,cooldown:0});advance(restored.s,40);assert.equal(restored.s.pending,null);
  restored.s.progress({progress_value:3});advance(restored.s,15.1);assert.ok(restored.s.pending);
  assert.ok(restored.journal.some(e=>e.type==='progress'));
});

test('timing-v2 proactive offers before failure; reactive needs two explicit failures',()=>{
  const proactive=setup(),reactive=setup('reactive');
  advance(proactive.s,15.1);advance(reactive.s,60);
  assert.equal(shown(proactive).length,1);assert.equal(proactive.s.pending.trigger_reason,'idle');
  assert.equal(reactive.s.pending,null);
  reactive.s.failure('collision',{kind:'spinner'});assert.equal(reactive.s.pending,null);
  reactive.s.failure('collision',{kind:'spinner'});reactive.s.tick(0,true,false);
  assert.equal(shown(reactive).length,1);assert.equal(reactive.s.pending.trigger_family,'reactive');
});

test('first proactive error cancels queued or shown invitation and survives progress and returning to the scope',()=>{
  for(const safe of [false,true]){
    const f=setup();advance(f.s,15.1,{safe});assert.ok(f.s.pending);
    f.s.failure('fall');assert.equal(f.s.pending,null);assert.equal(f.s.shown,false);
    f.s.progress({progress_value:10});advance(f.s,60);assert.equal(f.s.pending,null);
    f.s.setScope(target('obstacle:bridge'));advance(f.s,15.1);assert.ok(f.s.pending);
    f.s.setScope(target());advance(f.s,60);assert.equal(f.s.pending,null);
    assert.equal(f.s.current.failed,true);
    assert.ok(f.events.some(e=>e.name==='scaffold_invitation_cancelled'&&e.data.cancel_reason==='first_explicit_failure'));
  }
});

test('saved first failure suppresses proactive after refresh and same-lesson retry',()=>{
  const saved={scopes:{'obstacle:spinner':{failed:true,failures:1,errors:1,shown_failure:0}},shown:0,cooldown:0};
  const f=setup('proactive',saved);advance(f.s,100);assert.equal(f.s.pending,null);
  f.s.setScope(target('obstacle:gates'));advance(f.s,15.1);assert.ok(f.s.pending);
  f.s.setScope(target());f.s.success();advance(f.s,100);assert.equal(f.s.pending,null);
  assert.equal(f.s.current.failed,true,'success must not erase historical first failure in the same lesson');
});

test('different obstacle mistakes are isolated; returning preserves two-error eligibility',()=>{
  const f=setup('reactive');f.s.failure('fall');
  f.s.setScope(target('obstacle:bridge'));f.s.failure('fall');assert.equal(f.s.pending,null);
  f.s.setScope(target());f.s.failure('fall');assert.ok(f.s.pending);
  assert.equal(f.s.current.failures,2);assert.equal(f.s.saved.scopes['obstacle:bridge'].failures,1);
});

test('reactive eligibility reached during cooldown is offered when cooldown finishes',()=>{
  const f=setup('reactive');f.s.open();f.s.close();
  f.s.failure('fall');f.s.failure('fall');assert.equal(f.s.pending,null);
  advance(f.s,29.9);assert.equal(f.s.pending,null);
  advance(f.s,.2);assert.ok(f.s.pending);assert.equal(shown(f).length,1);
});

test('later reminds a reactive invitation after 30 active seconds and counts another display',()=>{
  const f=setup('reactive');f.s.failure('fall');f.s.failure('fall');f.s.tick(0,true,false);
  f.s.decide('dismissed');advance(f.s,29.9);assert.equal(f.s.pending,null);
  advance(f.s,.2);assert.ok(f.s.pending);assert.equal(shown(f).length,2);
});

test('rejecting reactive help is not undone by returning to the scope or restoring state',()=>{
  const f=setup('reactive');f.s.failure('fall');f.s.failure('fall');f.s.tick(0,true,false);f.s.decide('rejected');
  advance(f.s,31);assert.equal(f.s.pending,null);
  f.s.setScope(target('obstacle:bridge'));f.s.setScope(target());advance(f.s,31);assert.equal(f.s.pending,null);
  const saved={scopes:{'obstacle:spinner':{failed:true,failures:2,errors:2,shown_failure:2}},shown:1,cooldown:0};
  const restored=setup('reactive',saved);advance(restored.s,31);assert.equal(restored.s.pending,null);
});

test('ordinary quiz hesitation displays before a response and stops after first wrong response',()=>{
  const f=setup();f.s.quizStart({task_id:'question_1'});advance(f.s,14.9);assert.equal(f.s.pending,null);
  advance(f.s,.2);assert.equal(shown(f).length,1);assert.equal(f.s.pending.source,'quiz_hesitation');
  f.s.quizResult(false,{task_id:'question_1'});advance(f.s,30);assert.equal(f.s.pending,null);
});

test('safety thresholds use original 24/18/15 second budgets and feedback does not accrue time',()=>{
  for(const budget of [24,18,15]){
    const f=setup();f.s.setScope(target('case:first','safety',{budget}));
    advance(f.s,budget/2-.05);assert.equal(f.s.pending,null);
    advance(f.s,.1);assert.equal(shown(f).length,1);assert.equal(f.s.pending.source,'quiz_hesitation');
    const before=f.s.now;f.s.tick(40,false,false);assert.equal(f.s.now,before);
  }
});

test('two wrong safety dossiers offer in existing feedback without advancing its clock; success resets streak',()=>{
  const f=setup('reactive');f.s.setScope(target('case:one','safety',{budget:24}));
  f.s.quizResult(false,{safety:true});assert.equal(f.s.pending,null);
  f.s.setScope(target('case:two','safety',{budget:24}));f.s.quizResult(false,{safety:true});
  const before=f.s.now;assert.equal(f.s.tick(0,true,false),true);assert.equal(f.s.now,before);
  assert.equal(f.s.pending.scope_id,'case:two');assert.equal(shown(f).length,1);
  f.s.setScope(target('case:three','safety',{budget:24}));f.s.quizResult(true,{safety:true});
  assert.equal(f.s.safetyErrors,0);f.s.setScope(target('case:four','safety',{budget:18}));
  f.s.quizResult(false,{safety:true});assert.equal(f.s.pending,null);
});

test('uncalibrated bomb target offers at ten seconds, completed calibration cancels and disables it',()=>{
  const f=setup();f.s.setScope(target('wave:1','calibration'));
  advance(f.s,9.9);assert.equal(f.s.pending,null);advance(f.s,.2);assert.equal(shown(f).length,1);
  f.s.setScope(target('wave:1','calibration',{eligible:false}));assert.equal(f.s.pending,null);
  advance(f.s,30);assert.equal(f.s.pending,null);
});

test('an invitation keeps active time running; acceptance suspends it until support closes',()=>{
  const f=setup();advance(f.s,15.1);const before=f.s.now;advance(f.s,3);
  assert.ok(f.s.now>=before+2.99);assert.equal(shown(f).length,1);assert.equal(f.s.support,null);
  const context=f.s.decide('accepted');assert.equal(f.s.support.scaffold_id,context.scaffold_id);
  const acceptedAt=f.s.now;advance(f.s,20);assert.equal(f.s.now,acceptedAt);
  f.s.close();advance(f.s,1);assert.ok(f.s.now>acceptedAt);
});

test('automatic quota is three displays including later, manual help does not consume it',()=>{
  const f=setup();
  for(let i=0;i<3;i++){advance(f.s,i===0?15.1:30.1);assert.equal(shown(f).length,i+1);f.s.decide('dismissed');}
  advance(f.s,100);assert.equal(f.s.pending,null);assert.equal(f.s.count,3);
  f.s.open();f.s.hintShown();f.s.close();assert.equal(f.s.count,3);
  assert.equal(f.journal.filter(e=>e.type==='shown').length,3);
});

test('quota and cooldown survive a saved session',()=>{
  const quota=setup('proactive',{shown:3,scopes:{}});advance(quota.s,100);assert.equal(quota.s.pending,null);
  const cooldown=setup('proactive',{shown:1,cooldown:30,scopes:{}});
  advance(cooldown.s,29.9);assert.equal(cooldown.s.pending,null);advance(cooldown.s,.2);assert.ok(cooldown.s.pending);
});

test('answer attribution records only a shown hint, keeps manual origin after closing, and does not leak into other scopes',()=>{
  const f=setup();f.s.quizStart({task_id:'one'});const manual=f.s.open();
  assert.equal(f.s.attribution().ai_used_before_response,false);f.s.hintShown();f.s.close();
  const attributed=f.s.attribution();assert.equal(attributed.support_trigger,'manual');assert.equal(attributed.trigger_family,'manual');
  assert.equal(attributed.scaffold_id,manual.scaffold_id);assert.equal(attributed.hint_count_before_response,1);
  f.s.quizStart({task_id:'two'});assert.equal(f.s.attribution().ai_used_before_response,false);
  f.s.quizStart({task_id:'one'});assert.equal(f.s.attribution().scaffold_id,manual.scaffold_id);
});

test('automatic answer attribution retains proactive family after AI closes',()=>{
  const f=setup();advance(f.s,15.1);const accepted=f.s.decide('accepted');f.s.hintShown();f.s.close();
  const attributed=f.s.attribution();assert.equal(attributed.trigger_family,'proactive');assert.equal(attributed.support_trigger,'idle');
  assert.equal(attributed.scaffold_id,accepted.scaffold_id);assert.equal(attributed.scaffold_policy_version,POLICY);
});

test('persisted shown hint keeps attribution after refresh, but a different scope receives none',()=>{
  const last_hint={scope_id:'quiz:one',scaffold_id:'run-hint-one',trigger_reason:'no_progress',trigger_family:'proactive'};
  const f=setup('proactive',{scopes:{'quiz:one':{failed:false,failures:0,errors:0,hint_count:2,last_hint}},shown:1});
  f.s.quizStart({task_id:'one'});assert.equal(f.s.attribution().scaffold_id,'run-hint-one');
  assert.equal(f.s.attribution().hint_count_before_response,2);assert.equal(f.s.attribution().trigger_family,'proactive');
  f.s.quizStart({task_id:'two'});assert.equal(f.s.attribution().ai_used_before_response,false);
});

test('same no-progress trace triggers after 25 seconds regardless of frame duration',()=>{
  const first=[];
  for(const hz of [30,60,144]){
    const f=setup();const dt=1/hz;
    for(let i=0;i<hz*27&&!f.s.shown;i++){f.s.activity({movement:'moving'});f.s.tick(dt,true);}
    const event=shown(f)[0];assert.ok(event);assert.equal(event.data.trigger_reason,'no_progress');
    assert.ok(event.data.active_elapsed>=RULES.noProgress-1e-6);assert.ok(event.data.active_elapsed<=RULES.noProgress+dt+1e-6);
    first.push(event.data.active_elapsed);
  }
  assert.ok(Math.max(...first)-Math.min(...first)<=1/30+1e-6);
});

test('two recent reversals with no progress trigger after twelve seconds, pause cannot contribute',()=>{
  const f=setup();f.s.observe(10);advance(f.s,4);f.s.observe(8);f.s.activity();
  advance(f.s,4);f.s.observe(10);f.s.activity();advance(f.s,3.9);f.s.observe(8);f.s.activity();
  f.s.tick(100,true,false);assert.equal(f.s.pending,null);
  advance(f.s,.2);assert.equal(f.s.pending.source,'repeated_movement');
});
