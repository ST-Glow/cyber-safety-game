import test from 'node:test';
import assert from 'node:assert/strict';
import {ScaffoldStore} from '../src/scaffold-store.js';

class Storage {constructor(){this.items=new Map();}getItem(k){return this.items.get(k)||null;}setItem(k,v){this.items.set(k,v);}}
function fixture(){
  const storage=new Storage(),calls=[],committed=new Map();let online=true,loseResponse=false,wait=null;
  const client={run:{lesson_id:'lesson1'},snapshot:{account:{id:'student1'}},storage,
    api:async(path,body)=>{
      if(!online)throw Error('offline');if(wait)await wait;
      calls.push({path,body:structuredClone(body)});
      if(!body)return {state:{seen:[...committed.values()]}};
      for(const e of body.events)committed.set(body.client_id+':'+e.seq,e);
      const acknowledged=Math.max(...[...committed.keys()].filter(k=>k.startsWith(body.client_id+':')).map(k=>Number(k.split(':').at(-1))));
      if(loseResponse){loseResponse=false;throw Error('response lost after server commit');}
      return {acknowledged,state:{seen:[...committed.values()]}};
    }};
  return {client,storage,calls,committed,offline:()=>online=false,online:()=>online=true,lose:()=>loseResponse=true,delay:p=>wait=p};
}

test('offline failure journal is written before network and replays with original sequence on refresh',async()=>{
  const f=fixture();f.offline();const s=new ScaffoldStore(f.client,'ai_training_ground');
  s.push({type:'failure',scope_id:'obstacle:spinner'});await assert.rejects(s.flush());
  const persisted=JSON.parse(f.storage.getItem(s.key));assert.equal(persisted.events.length,1);assert.equal(persisted.events[0].seq,1);
  const restored=new ScaffoldStore(f.client,'ai_training_ground');assert.equal(restored.record.client_id,persisted.client_id);
  f.online();const state=await restored.load();assert.equal(state.seen.length,1);assert.deepEqual(state.seen[0],persisted.events[0]);
  assert.equal(restored.record.events.length,0);assert.equal(restored.record.seq,1);
});

test('response loss retries exactly the same event identity without double-counting the server commit',async()=>{
  const f=fixture();f.lose();const s=new ScaffoldStore(f.client,'ai_training_ground');
  s.push({type:'failure',scope_id:'obstacle:spinner'});await assert.rejects(s.flush());assert.equal(f.committed.size,1);
  await s.flush();assert.equal(f.committed.size,1);assert.equal(s.record.events.length,0);
  assert.deepEqual(f.calls[0].body.events,f.calls[1].body.events);assert.equal(f.calls[0].body.client_id,f.calls[1].body.client_id);
});

test('a flush captures events appended during a pending request in order and coalesces concurrent flushes',async()=>{
  const f=fixture();let release;f.delay(new Promise(resolve=>release=resolve));const s=new ScaffoldStore(f.client,'ai_training_ground');
  s.push({type:'failure',scope_id:'obstacle:spinner'});const one=s.flush();
  s.push({type:'shown',scope_id:'obstacle:spinner',family:'reactive'});const two=s.flush();
  release();await Promise.all([one,two]);assert.deepEqual([...f.committed.values()].map(e=>e.seq),[1,2]);
  assert.equal(s.record.events.length,0);assert.equal(f.calls.filter(c=>c.body).length,2);
});

test('journals cannot cross accounts, lessons, or levels',async()=>{
  const f=fixture();f.offline();const original=new ScaffoldStore(f.client,'ai_training_ground');
  original.push({type:'failure',scope_id:'obstacle:spinner'});await assert.rejects(original.flush());
  for(const [account,lesson,level] of [['student2','lesson1','ai_training_ground'],['student1','lesson2','ai_training_ground'],['student1','lesson1','spinner_race']]){
    const client={...f.client,snapshot:{account:{id:account}},run:{lesson_id:lesson}};
    const other=new ScaffoldStore(client,level);assert.notEqual(other.key,original.key);assert.equal(other.record.events.length,0);
  }
  assert.equal(JSON.parse(f.storage.getItem(original.key)).events.length,1);
});
