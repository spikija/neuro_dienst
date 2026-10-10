// Isolated tests: default PostgreSQL/WASM; optional local empty PostgreSQL DB.
// node supabase/tests/admin_assignments.mjs <directory containing @electric-sql/pglite>
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const require = createRequire(path.resolve(process.argv[2], 'package.json'));
const native = process.argv.includes('--postgres');
const safeupdate = process.argv.includes('--safeupdate');
if (safeupdate && !native) throw new Error('--safeupdate requires --postgres and the native safeupdate module');
let db;
let openConnection;
if (native) {
  const url = new URL(process.env.NEURO_ADMIN_TEST_DATABASE_URL ?? '');
  if (!['localhost','127.0.0.1','[::1]'].includes(url.hostname) || !url.pathname.startsWith('/neuro_admin_test_')) {
    throw new Error('Only a local disposable neuro_admin_test_* database is allowed');
  }
  const { Client } = require('pg');
  openConnection = async () => {
    const client = new Client({connectionString:url.toString()}); await client.connect();
    if (safeupdate) {
      // Fixture setup intentionally exercises unqualified legacy writes too.
      // Enable the actual guard for RPC execution through its function setting.
      await client.query("LOAD 'safeupdate'; SET safeupdate.enabled=off");
    }
    return client;
  };
  const client = await openConnection();
  const tables = await client.query("select count(*)::int as n from pg_tables where schemaname not in ('pg_catalog','information_schema')");
  if (tables.rows[0].n !== 0) { await client.end(); throw new Error('Disposable database must be empty'); }
  db = {query:(...args)=>client.query(...args),exec:sql=>client.query(sql),close:()=>client.end()};
} else {
  const { PGlite } = require('@electric-sql/pglite');
  db = new PGlite();
}
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
await db.exec(`do $$begin if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if; end$$; create schema auth;
create table auth.users(id uuid primary key);
create function auth.jwt() returns jsonb language sql stable as $$select current_setting('request.jwt.claims',true)::jsonb$$;
create function auth.uid() returns uuid language sql stable as $$select (auth.jwt()->>'sub')::uuid$$;
grant usage on schema auth to authenticated;`);
for (const name of (await readdir(path.join(root, 'migrations'))).sort()) {
  const sql = (await readFile(path.join(root,'migrations',name),'utf8')).replace('create extension if not exists pgcrypto;','');
  await db.exec(sql);
}
if (safeupdate) await db.exec("alter function public.admin_apply_assignments(uuid,bigint,uuid,uuid,date[],uuid,text) set safeupdate.enabled=on");
if (safeupdate) await db.exec("alter function public.admin_apply_generation(int,int,uuid,bigint,text,uuid) set safeupdate.enabled=on; alter function public.admin_remove_assignments(uuid,bigint,date[],text,uuid,uuid,text) set safeupdate.enabled=on");
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
await db.exec(`grant usage on schema public to authenticated;
grant select on public.rosters, public.roster_slots, public.roster_days, public.assignments, public.audit_log to authenticated;
insert into auth.users values ('${id(1)}'),('${id(2)}'),('${id(3)}');
insert into public.profiles(id,role,display_name) values ('${id(1)}','admin','Admin'),('${id(2)}','doctor','Doctor'),('${id(3)}','viewer','Viewer');
insert into public.doctors(id,first_name,last_name,rank,capabilities) values
('${id(10)}','Ana','Test','consultant','{can_lead}'),('${id(11)}','Ben','Test','resident','{}');
insert into public.roles(id,code,name,allowed_ranks,required_capabilities) values
('${id(20)}','TEST','Test role','{consultant}','{can_lead}');
insert into public.rosters(id,year,month) values ('${id(30)}',2026,10);
insert into public.roster_days(id,roster_id,date) values
('${id(40)}','${id(30)}','2026-10-05'),('${id(41)}','${id(30)}','2026-10-06'),('${id(42)}','${id(30)}','2026-10-07');
insert into public.roster_slots(id,roster_day_id,role_id,starts_at,ends_at) values
('${id(50)}','${id(40)}','${id(20)}','2026-10-05T08:00Z','2026-10-05T12:00Z'),
('${id(51)}','${id(41)}','${id(20)}','2026-10-06T08:00Z','2026-10-06T12:00Z'),
('${id(52)}','${id(42)}','${id(20)}','2026-10-07T08:00Z','2026-10-07T12:00Z');`);
async function login(user=1,aal='aal2') {
  await db.exec('reset role');
  await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:user ? id(user):null,aal})]);
  await db.exec('set role authenticated');
}
const version = async () => Number((await db.query(`select content_version from rosters where id='${id(30)}'`)).rows[0].content_version);
const count = async table => Number((await db.query(`select count(*) as n from ${table}`)).rows[0].n);
async function apply({dates=['2026-10-05'],expected,request=70,physician=10,role=id(20),reason=null}={}) {
  const v=expected ?? await version();
  return (await db.query('select public.admin_apply_assignments($1,$2,$3,$4,$5::date[],$6,$7) as value',
    [id(30),v,id(physician),role,dates,id(request),reason])).rows[0].value;
}
const codes = result => result.results.flatMap(r=>r.errors);
let tests=0;
async function test(name,run) {
  await db.exec('reset role; begin;');
  try { await run(); tests++; console.log(`PASS ${name}`); }
  finally { await db.exec('rollback; reset role;'); }
}
const preview = async(year=2027,month=4,roster=null) => (await db.query('select admin_preview_generation($1,$2,$3) value',[year,month,roster])).rows[0].value;
const generate = async(p,request=800) => (await db.query('select admin_apply_generation($1,$2,$3,$4,$5,$6) value',
 [p.plan.year,p.plan.month,p.plan.rosterId,p.plan.existingVersion,p.token,id(request)])).rows[0].value;
const remove = async({scope='role',role=id(20),dates=['2026-10-05'],expected,request=900,reason=null}={}) =>
 (await db.query('select admin_remove_assignments($1,$2,$3::date[],$4,$5,$6,$7) value',[id(30),expected??await version(),dates,scope,role,id(request),reason])).rows[0].value;
await test('national holidays across years and beyond 2037',async()=>{
 assert.equal((await db.query("select austrian_holiday('2008-05-01') name")).rows[0].name,'Staatsfeiertag; Christi Himmelfahrt');
 for(const [date,name] of [['2026-04-06','Ostermontag'],['2026-05-14','Christi Himmelfahrt'],['2026-05-25','Pfingstmontag'],['2026-06-04','Fronleichnam'],['2040-04-02','Ostermontag'],['2100-10-26','Nationalfeiertag']]) {
 assert.equal((await db.query('select austrian_holiday($1) name',[date])).rows[0].name,name);
 }
});
for(const [user,aal,code] of [[2,'aal2','unauthorized'],[3,'aal2','unauthorized'],[0,'aal2','unauthorized'],[1,'aal1','mfaRequired']]) {
 await test(`workspace denies ${user}/${aal}`,async()=>{
 await login(user,aal); assert.equal((await preview()).code,code); assert.equal((await remove()).code,code);
 assert.equal((await db.query('select admin_apply_generation(2027,4,null,null,\'x\',$1) value',[id(800)])).rows[0].value.code,code);
 });
}
await test('new month atomic creation holiday metadata Vienna instants and idempotency',async()=>{
 await login(); const p=await preview(2026,5); assert.equal(p.ok,true); assert.equal(p.plan.days.length,31);
 assert.equal(p.plan.days.filter(d=>d.holidayName).length,3);
 const first=p.plan.slots[0]; const template=p.plan.templates.find(t=>t.templateId===first.templateId); assert.equal(new Date(first.startsAt).getUTCHours(),Number(template.start.slice(0,2))-2);
 const r=await generate(p); assert.equal(r.ok,true); assert.equal(r.phase,'draft');
 assert.deepEqual(await generate(p),r); assert.equal((await preview(2026,5)).plan.blockers[0],'monthExists');
 const holidays=(await db.query('select count(*)::int n from roster_days where roster_id=$1 and is_public_holiday',[r.rosterId])).rows[0].n;
 assert.equal(holidays,3);
 assert.equal((await db.query("select count(*)::int n from audit_log where action='admin_create_roster'")).rows[0].n,1);
});
await test('monthly recurrence includes weekend and skips impossible day',async()=>{
 await db.exec(`insert into role_templates(role_id,weekday_rule,monthly_day,start_time,end_time) values('${id(20)}','monthly_day',31,'09:00','10:00')`);
 await login(); let p=await preview(2027,4); assert.equal(p.plan.slots.filter(s=>s.roleId===id(20)).length,0);
 p=await preview(2027,1); assert.equal(p.plan.slots.filter(s=>s.roleId===id(20)).length,1);
 assert.equal(p.plan.slots.find(s=>s.roleId===id(20)).date,'2027-01-31');
});
await test('published generation never overwrites; occupied removed slot blocks draft regeneration',async()=>{
 await login(); await apply(); const p=await preview(2026,10,id(30));
 assert.ok(p.plan.blockers.includes('assignmentLoss')); assert.equal((await generate(p)).code,'generationBlocked');
 await db.exec("reset role; update rosters set phase='published' where year=2026 and month=10"); await login();
 assert.ok((await preview(2026,10,id(30))).plan.blockers.includes('draftRequired'));
 assert.equal(await count('assignments'),1);
});
await test('regeneration preserves occupied matching slot identities',async()=>{
 await db.exec(`insert into role_templates(role_id,weekday_rule,start_time,end_time) values('${id(20)}','every_weekday','10:00','14:00')`);
 await login(); await apply(); const p=await preview(2026,10,id(30)); assert.deepEqual(p.plan.blockers,[]);
 assert.ok(p.plan.slots.some(s=>s.existingSlotId===id(50)));
 assert.equal((await generate(p)).ok,true); assert.equal(await count('assignments'),1);
 assert.equal((await db.query('select roster_slot_id from assignments')).rows[0].roster_slot_id,id(50));
});
await test('template changes invalidate generation preview',async()=>{
 await login(); const p=await preview(); await db.exec("reset role; update role_templates set start_time='07:00' where weekday_rule='every_weekday'"); await login();
 assert.equal((await generate(p)).code,'staleVersion');
});
await test('generation audit failure rolls back entire new roster',async()=>{
 await db.exec("create function public.fail_workspace_audit() returns trigger language plpgsql as $$begin raise exception 'test'; end$$; create trigger fail_workspace before insert on audit_log for each row execute function fail_workspace_audit()");
 await login(); const before=await count('rosters'); const days=await count('roster_days'); const slots=await count('roster_slots');
 assert.equal((await generate(await preview())).code,'internalError');
 assert.equal(await count('rosters'),before); assert.equal(await count('roster_days'),days); assert.equal(await count('roster_slots'),slots);
});
await test('role removal preserves unrelated assignments and reports no-op dates; retry audited once',async()=>{
 await login(); await apply({dates:['2026-10-05','2026-10-06']}); const expected=await version();
 const r=await remove({dates:['2026-10-05','2026-10-07'],expected}); assert.equal(r.ok,true); assert.equal(r.removedAssignments.length,1);
 assert.equal(await count('assignments'),1); assert.equal(await count('roster_slots'),3);
 assert.deepEqual(await remove({dates:['2026-10-05','2026-10-07'],expected}),r);
 assert.equal((await db.query("select count(*)::int n from audit_log where action='admin_remove_assignment'")).rows[0].n,1);
});
await test('all role removal and strict scope parameters',async()=>{
 await login(); await apply({dates:['2026-10-05','2026-10-06']});
 assert.equal((await remove({scope:'all'})).code,'invalidRequest');
 const r=await remove({scope:'all',role:null,dates:['2026-10-05','2026-10-06']}); assert.equal(r.removedAssignments.length,2); assert.equal(await count('assignments'),0);
});
await test('removal lifecycle reason stale-version and idempotency conflict',async()=>{
 await login(); await apply(); const old=await version();
 await db.exec("reset role; update rosters set phase='locked' where year=2026 and month=10"); await login();
 assert.equal((await remove({expected:old})).code,'staleVersion');
 assert.equal((await remove()).code,'rosterNotEditable'); assert.equal((await remove({reason:'   '})).code,'rosterNotEditable');
 assert.equal((await remove({reason:'Correction'})).ok,true); assert.equal((await remove({reason:'Changed'})).code,'idempotencyConflict');
 await db.exec("reset role; update rosters set phase='published' where year=2026 and month=10"); await login();
 assert.equal((await remove({request:901})).code,'rosterNotEditable');
});
await test('removal audit failure rolls back every deletion and version',async()=>{
 await login(); await apply({dates:['2026-10-05','2026-10-06']}); await db.exec("reset role; create function public.fail_workspace_audit() returns trigger language plpgsql as $$begin raise exception 'test'; end$$; create trigger fail_workspace before insert on audit_log for each row execute function fail_workspace_audit()");
 await login(); const v=await version(); assert.equal((await remove({scope:'all',role:null,dates:['2026-10-05','2026-10-06']})).code,'internalError');
 assert.equal(await count('assignments'),2); assert.equal(await version(),v);
});
await test('generation rejects DST gaps and folds in monthly templates',async()=>{
 await db.exec(`insert into role_templates(role_id,weekday_rule,monthly_day,start_time,end_time) values('${id(20)}','monthly_day',29,'02:30','04:00')`);
 await login(); assert.ok((await preview(2026,3)).plan.blockers.includes('ambiguousOrMissingWallTime'));
 await db.exec(`reset role; update role_templates set monthly_day=25 where role_id='${id(20)}'`); await login();
 assert.ok((await preview(2026,10)).plan.blockers.includes('ambiguousOrMissingWallTime'));
});
await test('all roles really includes distinct roles; selected role leaves the other role',async()=>{
 await db.exec(`insert into roster_slots(id,roster_day_id,role_id,starts_at,ends_at) select '${id(53)}','${id(40)}',id,'2026-10-05T14:00Z','2026-10-05T16:00Z' from roles where code='SCI';
 insert into assignments(roster_slot_id,doctor_id) values('${id(53)}','${id(11)}')`);
 await login(); await apply(); assert.equal((await remove()).removedAssignments.length,1); assert.equal(await count('assignments'),1);
 const all=await remove({scope:'all',role:null,request:901}); assert.equal(all.removedAssignments.length,1);
 assert.equal(all.removedAssignments[0].physicianId,id(11));assert.equal(await count('assignments'),0);
});
if(native) {
 await login(); const p=await preview(2028,2);
 const clients=await Promise.all([openConnection(),openConnection()]);
 try {
 for(const c of clients) { await c.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:id(1),aal:'aal2'})]);await c.query('set role authenticated'); }
 const results=await Promise.all(clients.map((c,n)=>c.query('select admin_apply_generation(2028,2,null,null,$1,$2) value',[p.token,id(1800+n)])));
 assert.equal(results.filter(r=>r.rows[0].value.ok===true).length,1);
 assert.equal(results.filter(r=>r.rows[0].value.code==='generationBlocked').length,1);
 tests++;console.log('PASS concurrent native creation commits exactly one roster');
 await apply(); const v=await version();
 const removals=await Promise.all(clients.map((c,n)=>c.query("select admin_remove_assignments($1,$2,ARRAY['2026-10-05'::date],'role',$3,$4,null) value",[id(30),v,id(20),id(1900+n)])));
 assert.equal(removals.filter(r=>r.rows[0].value.ok===true).length,1);
 assert.equal(removals.filter(r=>r.rows[0].value.code==='staleVersion').length,1);
 tests++;console.log('PASS concurrent native removal rejects stale contender');
 } finally {await Promise.all(clients.map(c=>c.end()));}
}
console.log(`${tests} isolated workspace PostgreSQL tests passed.`);
await db.close();
