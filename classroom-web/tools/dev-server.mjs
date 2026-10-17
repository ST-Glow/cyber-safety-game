// Local acceptance fixture. Binds loopback only; never included by build.mjs.
import {createRequire} from 'node:module';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const require=createRequire(import.meta.url),root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const express=require(path.join(root,'cloud/aliyun-upload-api/node_modules/express'));
const {createSqliteStore}=require(path.join(root,'cloud/aliyun-upload-api/src/classroom/store.js'));
const {ClassroomService}=require(path.join(root,'cloud/aliyun-upload-api/src/classroom/service.js'));
const {mountClassroom}=require(path.join(root,'cloud/aliyun-upload-api/src/classroom/routes.js'));
const store=await createSqliteStore(':memory:'),service=new ClassroomService(store,{linkSecret:'local-native-acceptance-only-secret-20260910'});
await service.bootstrap('teacher','NativeTeacher123!');const teacher=(await service.login('teacher','NativeTeacher123!',true)).token;
const students=await service.batchStudents(teacher,2,'NATIVE');for(const s of students){const t=await service.login(s.username,s.initial_password);await service.changePassword(t.token,s.initial_password,'NativeStudent123!');}
const localUploads=process.env.NATIVE_LOCAL_UPLOADS==='1';
await service.lesson(teacher,'open',localUploads?'本机演示 · 数据不上传云端':'原生版本地验收',crypto.randomUUID());
// A fixed local-only wallet exercises preview and purchases without touching any cloud account.
await store.transaction(async tx=>{for(const s of await tx.list('accounts',{role:'student'})){s.balance=500;await tx.put('accounts',s.id,s);}});
if(process.env.NATIVE_EXPERIMENT_QA==='1'){
  for(const [condition,prefix] of [['proactive','QA_A'],['reactive','QA_B']]){
    const made=await service.createClass(teacher,{condition,name:'本机'+condition,request_id:'fixture-'+condition});
    const classId=made.class_id,rows=await service.batchStudents(teacher,2,prefix,classId);
    for(const row of rows){const login=await service.login(row.username,row.initial_password);await service.changePassword(login.token,row.initial_password,'NativeStudent123!');}
    await service.lesson(teacher,'open','本机双班验收',crypto.randomUUID(),'',classId);
  }
}
const app=express(),port=Number(process.env.NATIVE_DEV_PORT||8792),json=express.json();app.use((req,res,next)=>req.method==='PUT'?next():json(req,res,next));
app.get('/classroom/native/config.js',(_req,res)=>res.type('js').send(`window.NATIVE_CONFIG={apiBaseUrl:'http://127.0.0.1:${port}',fallbackApiBaseUrl:''};window.GODOT_CLASSROOM_CONFIG={enabled:true};window.GODOT_EXPERIMENT_CONFIG={productionMode:true,studentView:true,deploymentStage:'preview',consentMode:'adult',recordingFps:30,recordingBitsPerSecond:1500000,recordingChunkBatchSize:15,primaryApiBaseUrl:'http://127.0.0.1:${port}',studyVersion:'local-native-acceptance',retentionMonths:12,researchContact:'本机隔离验收，不连接云端'};`));
app.post('/api/coze/chat',(_req,res)=>res.json({reply:'这是本机验收提示。先停在安全处，观察旋转杆。杆扫过后，再跳跃向前。穿闸门时，看准能让角色通过的高度。',session:'local-only'}));
app.use('/classroom/native',express.static(path.join(root,'classroom-web'),{index:'index.html',setHeaders:r=>r.setHeader('Cache-Control','no-store')}));
for(const group of ['a','b'])app.get('/classroom/'+group+'/',(_req,res)=>res.sendFile(path.join(root,'classroom-web/index.html')));
app.use('/legacy',express.static(path.join(root,'dist/classroom-preview-site/classroom/game')));
mountClassroom(app,{service});
if(localUploads){
  const {createApp}=require(path.join(root,'cloud/aliyun-upload-api/src/create-app.js'));
  // Explicit local preview only: the real ticket/file/manifest validators write to a local directory.
  app.use(createApp({config:{linkSecret:'local-native-acceptance-only-secret-20260910',allowedOrigins:['http://127.0.0.1:'+port],mockRoot:path.join(root,'tmp/native/local-preview-uploads'),publicBaseUrl:'http://127.0.0.1:'+port},coze:{configured:false}}));
}
app.listen(port,'127.0.0.1',()=>console.log('NATIVE_LOCAL_READY http://127.0.0.1:'+port+'/classroom/native/ (isolated in-memory database)'));

