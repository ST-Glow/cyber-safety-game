export const POLICY='timing-v2';
export const RULES=Object.freeze({grace:10,idle:15,noProgress:25,quizHesitation:15,failure:2,quizErrors:2,strategyWindow:30,cooldown:30,later:30,limit:3,epsilon:1.5,movementWindow:12});
export class ExperimentScaffold {
  constructor({condition,lessonId='',levelId='',objective='',emit=()=>{},state=()=>({}),saved={},persist=()=>{}}={}){
    Object.assign(this,{condition,lessonId,levelId,objective,emit,state,persist});this.saved=structuredClone(saved);this.saved.scopes||={};this.count=this.saved.shown||0;this.cooldown=this.saved.cooldown||0;this.safetyErrors=this.saved.safety_errors||0;
    this.now=0;this.pending=null;this.support=null;this.shown=false;this.quiz=false;this.failures=[];this.quizResults=[];this.hints=new Map(Object.entries(this.saved.scopes).filter(([,v])=>v.last_hint).map(([k,v])=>[k,{...v.last_hint,hint_count:v.hint_count}]));this.strategies=new Map();this.lastCooldown=this.cooldown;this.setScope({id:'start',kind:'movement'});
  }
  record(name,payload={}){this.emit(name,{...this.base(),...payload,condition:this.condition,scaffold_version:POLICY,scaffold_policy_version:POLICY,lesson_id:this.lessonId,active_elapsed:this.now,wall_time:new Date().toISOString()});}
  durable(type,details={}){this.persist({type,scope_id:this.scope.id,...details});}
  get current(){return this.saved.scopes[this.scope.id]||={failed:false,failures:0,errors:0,shown_failure:0,hint_count:0};}
  base(reason='',details={}){return {scope_id:this.scope?.id||'',trigger_reason:reason,trigger_family:reason==='manual'?'manual':this.condition,scaffold_id:'',failure_count_at_trigger:this.scope?this.current.failures:0,elapsed_without_progress:Math.max(0,this.now-(this.progressAt||0)),intervention_index:this.count,...details};}
  context(){return {...this.state(),condition:this.condition,level_id:this.levelId,lesson_id:this.lessonId,current_objective:this.objective,scope_id:this.scope.id,recent_failures:this.failures.slice(-8),recent_quiz_results:this.quizResults.slice(-8),elapsed_without_progress:this.now-this.progressAt,allowed_hint_level:3};}
  setScope(scope){
    if(this.scope?.id===scope.id){this.scope={...this.scope,...scope};if(scope.eligible===false&&this.condition==='proactive')this.cancel('objective_satisfied');return;}
    this.cancel('scope_changed');this.scope={kind:'movement',eligible:true,...scope};this.enteredAt=this.now;this.activityAt=this.now;this.progressAt=this.now;this.quizAt=this.now;this.best=null;this.observed=null;this.motion=null;this.direction=0;this.movements=[];this.rejected=new Set();this.lastCandidate='';this.suppressionKeys=new Set();this.record('scaffold_scope_entered');if(scope.id!=='start')this.durable('scope');
    if(this.condition==='reactive'&&this.current.errors>=2&&this.current.shown_failure<this.current.failures)this.consider('repeated_failure');
  }
  cancel(reason){if(this.pending)this.record('scaffold_invitation_cancelled',{...this.pending,cancel_reason:reason});this.pending=null;this.shown=false;}
  activity(choice={}){this.activityAt=this.now;if(this.after&&Object.keys(choice).length){this.record('choice_after_scaffold',{...this.after,choice});this.after=null;}}
  progress(details={}){if(this.current.declined){this.current.declined=false;this.durable('progress');}this.progressAt=this.now;this.activity(details);this.cancel('effective_progress');this.movements=[];this.direction=0;this.rejected.clear();this.lastCandidate='';this.suppressionKeys=new Set();this.record('scaffold_effective_progress',details);}
  success(details={}){this.current.errors=0;if(details.safety)this.safetyErrors=0;this.durable('success',details);this.progress(details);}
  observe(value){if(!Number.isFinite(value))return;if(this.best===null){this.best=value;this.observed=value;return;}const delta=value-this.observed;if(Math.abs(delta)>=RULES.epsilon){const d=Math.sign(delta);if(this.direction&&d!==this.direction)this.movements.push(this.now);this.direction=d;this.observed=value;}this.movements=this.movements.filter(t=>this.now-t<=12);if(value>=this.best+1.5){this.best=value;this.progress({progress_value:value});}}
  observeMotion(x,z){
    if(!this.motion){this.motion={x,z,dx:0,dz:0};return;}
    const m=this.motion,dx=x-m.x,dz=z-m.z,d=Math.hypot(dx,dz);if(d<1.5)return;
    if(m.dx*dx+m.dz*dz<-.5*d)this.movements.push(this.now);
    this.motion={x,z,dx:dx/d,dz:dz/d};this.movements=this.movements.filter(t=>this.now-t<=12);
  }
  failure(reason,details={}){
    const c=this.current;c.failed=true;c.failures++;c.errors++;if(details.safety)this.safetyErrors++;this.durable('failure',{safety:!!details.safety});this.failures.push({...details,reason,scope_id:this.scope.id,elapsed_seconds:this.now});
    if(this.condition==='proactive'){this.cancel('first_explicit_failure');this.record('scaffold_suppressed',{suppression_reason:'scope_already_failed'});return;}
    const key=this.scope.id+'|'+String(details.strategy||details.kind||reason),times=(this.strategies.get(key)||[]).filter(t=>this.now-t<=30);times.push(this.now);this.strategies.set(key,times);
    if((details.safety?this.safetyErrors:c.errors)>=2)this.consider(details.safety||reason==='quiz_error'?'quiz_error':times.length>=2?'repeated_strategy':'repeated_failure',{safety:!!details.safety});
  }
  quizStart(details={}){this.quiz=true;this.quizAt=this.now;if(details.task_id)this.setScope({id:'quiz:'+details.task_id,kind:'quiz'});}
  quizResult(correct,details={}){this.quizResults.push({...details,correct,elapsed_seconds:this.now});if(correct)this.success(details);else this.failure('quiz_error',details);}
  quizEnd(){this.quiz=false;}
  markSafe(){}
  consider(reason,details={}){
    const blocked=this.support?'help_open':this.condition==='proactive'&&this.scope.eligible===false?'objective_satisfied':this.count>=3?'lesson_level_quota':this.cooldown>0?'cooldown':this.pending?'invitation_pending':this.condition==='proactive'&&this.current.failed?'scope_already_failed':this.condition==='proactive'&&this.current.declined?'invitation_rejected':'';
    if(blocked){const key=reason+':'+blocked+':'+this.current.failures;if(!this.suppressionKeys.has(key)){this.suppressionKeys.add(key);this.record('scaffold_suppressed',{...this.base(reason),suppression_reason:blocked});}return;}
    const key=this.scope.id+':'+reason+':'+(this.condition==='reactive'?this.current.failures:this.progressAt);if(this.rejected.has(key))return;
    const context=this.base(reason,{...details,trigger_key:key,scaffold_id:this.levelId+'-'+crypto.randomUUID(),intervention_index:this.count+1});if(this.lastCandidate!==key){this.record('scaffold_eligible',context);this.lastCandidate=key;}this.pending=context;this.record('scaffold_triggered',context);
  }
  tick(dt,safe,active=true){
    if(this.support)return false;if(active){this.now+=dt;this.cooldown=Math.max(0,this.cooldown-dt);if(Math.abs(this.lastCooldown-this.cooldown)>=5||this.lastCooldown>0&&this.cooldown===0){this.lastCooldown=this.cooldown;this.durable('cooldown',{remaining:this.cooldown});}}
    if(!this.pending&&this.condition==='reactive'&&(this.current.remind||(this.scope.kind==='safety'?this.safetyErrors:this.current.errors)>=2&&this.current.shown_failure<this.current.failures))this.consider(this.current.last_reason||(this.scope.kind==='safety'?'quiz_error':'repeated_failure'),{safety:this.scope.kind==='safety'});
    if(active&&!this.pending&&this.condition==='proactive'&&!this.current.failed&&this.scope.eligible!==false){const age=this.now-this.enteredAt,kind=this.scope.kind,short=kind==='safety'||kind==='calibration';if(age>=(short?5:10)){
      if(kind==='safety'){if(age>=this.scope.budget/2)this.consider('no_progress',{source:'quiz_hesitation'});}
      else if(kind==='calibration'){if(this.now-this.progressAt>=10)this.consider('no_progress',{source:'calibration_wait'});}
      else if(kind==='quiz'){if(this.now-this.quizAt>=15)this.consider('no_progress',{source:'quiz_hesitation'});}
      else if(this.now-this.activityAt>=15)this.consider('idle');
      else if(this.movements.filter(t=>this.now-t<=12).length>=2&&this.now-this.progressAt>=12)this.consider('no_progress',{source:'repeated_movement'});
      else if(this.now-this.progressAt>=25)this.consider('no_progress');
    }}
    if(this.pending&&safe){if(!this.shown){this.shown=true;this.count++;this.current.shown_failure=this.current.failures;this.current.remind=false;this.current.last_reason=this.pending.trigger_reason;this.durable('shown',{family:this.condition,trigger_reason:this.pending.trigger_reason,scaffold_id:this.pending.scaffold_id,safety:!!this.pending.safety});this.record('scaffold_invitation_shown',this.pending);}return true;}return false;
  }
  decide(choice){if(!this.pending)return null;const context={...this.pending};this.record('scaffold_'+choice,context);this.pending=null;this.shown=false;this.current.remind=choice==='dismissed';if(choice==='accepted'){this.durable('decision',{choice});this.open(context);}else{if(choice==='rejected'){this.current.declined=true;this.rejected.add(context.trigger_key);}this.startCooldown(choice);}return context;}
  startCooldown(choice='closed'){this.cooldown=30;this.lastCooldown=30;this.durable('decision',{choice});}
  open(context){this.cancel('manual_help_opened');this.support=context||this.base('manual',{scaffold_id:this.levelId+'-manual-'+crypto.randomUUID()});this.record('choice_before_scaffold',{...this.support,choice:this.state().current_choice||{}});this.record('support_started',this.support);return this.support;}
  hintShown(){if(!this.support)return;const prior=this.hints.get(this.support.scope_id),hint={...this.support,hint_count:(prior?.hint_count||0)+1};this.hints.set(this.support.scope_id,hint);this.current.hint_count=hint.hint_count;this.current.last_hint=hint;this.durable('hint',{scaffold_id:hint.scaffold_id,trigger_reason:hint.trigger_reason,trigger_family:hint.trigger_family});}
  attribution(scopeId=this.scope.id){const h=this.hints.get(scopeId);return {ai_used_before_response:!!h,hint_count_before_response:h?.hint_count||0,hint_level:Math.min(h?.hint_count||0,3),support_trigger:h?.trigger_reason||'none',trigger_family:h?.trigger_family||'none',scaffold_id:h?.scaffold_id||'',scope_id:scopeId,scaffold_policy_version:POLICY};}
  close(){if(!this.support)return;this.record('support_ended',this.support);this.after=this.support;this.support=null;this.startCooldown();}
}
