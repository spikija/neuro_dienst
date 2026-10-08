// Isolated tests: default PostgreSQL/WASM; optional local empty PostgreSQL DB.
// node supabase/tests/admin_assignments.mjs <directory containing @electric-sql/pglite>
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const require = createRequire(path.resolve(process.argv[2], 'package.json'));
const native = process.argv.includes('--postgres');
let db;
let openConnection;
if (native) {
  const url = new URL(process.env.NEURO_ADMIN_TEST_DATABASE_URL ?? '');
  if (!['localhost','127.0.0.1','[::1]'].includes(url.hostname) || !url.pathname.startsWith('/neuro_admin_test_')) {
    throw new Error('Only a local disposable neuro_admin_test_* database is allowed');
  }
  const { Client } = require('pg');
  openConnection = async () => { const client = new Client({connectionString:url.toString()}); await client.connect(); return client; };
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
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
await db.exec(`grant usage on schema public to authenticated;
grant select on public.rosters, public.assignments, public.audit_log to authenticated;
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
async function apply({dates=['2026-10-05'],expected,request=70,physician=10,reason=null}={}) {
  const v=expected ?? await version();
  return (await db.query('select public.admin_apply_assignments($1,$2,$3,$4,$5::date[],$6,$7) as value',
    [id(30),v,id(physician),id(20),dates,id(request),reason])).rows[0].value;
}
const codes = result => result.results.flatMap(r=>r.errors);
let tests=0;
async function test(name,run) {
  await db.exec('reset role; begin;');
  try { await run(); tests++; console.log(`PASS ${name}`); }
  finally { await db.exec('rollback; reset role;'); }
}
await test('admin aal2 single creation, version and per-slot audit',async()=>{
  await login(); const v=await version(); const r=await apply({expected:v});
  assert.equal(r.ok,true); assert.equal(r.contentVersion,v+1); assert.equal(await count('assignments'),1);
  const audit=(await db.query('select * from audit_log')).rows[0];
  assert.equal(audit.actor_user_id,id(1)); assert.equal(audit.details.requestId,id(70));
  assert.equal(audit.details.newState,'confirmed'); assert.equal(audit.details.oldState,null);
  assert.equal(audit.details.date,'2026-10-05');
});
await test('multi-date all valid succeeds once and records every audit',async()=>{
  await login(); assert.equal((await apply({dates:['2026-10-05','2026-10-06']})).ok,true);
  assert.equal(await count('assignments'),2); assert.equal(await count('audit_log'),2);
});
for (const [user,aal,code] of [[2,'aal2','unauthorized'],[3,'aal2','unauthorized'],[0,'aal2','unauthorized'],[1,'aal1','mfaRequired']]) {
  await test(`access ${user}/${aal} rejected`,async()=>{
    const v=await version(); await login(user,aal);
    assert.equal((await apply({expected:v})).code,code);
    await db.exec('reset role'); assert.equal(await count('assignments'),0);
  });
}
await test('one missing slot rejects entire batch and version/audit stay unchanged',async()=>{
  await login(); const v=await version(); const r=await apply({dates:['2026-10-05','2026-10-08']});
  assert.equal(r.ok,false); assert.deepEqual(r.results.map(x=>x.errors),[[],['missingSlot']]);
  assert.equal(await count('assignments'),0); assert.equal(await count('audit_log'),0); assert.equal(await version(),v);
});
for (const [name,sql,options,code] of [
  ['inactive',`update doctors set is_active=false where id='${id(10)}'`,{},'physicianInactive'],
  ['role inactive',`update roles set is_active=false where id='${id(20)}'`,{},'roleInactive'],
  ['rank',null,{physician:11},'physicianNotEligible'],
  ['null rank metadata',`update roles set allowed_ranks=array[null]::public.doctor_rank[] where id='${id(20)}'`,{},'physicianNotEligible'],
  ['capability',`update doctors set capabilities='{}' where id='${id(10)}'`,{},'missingCapability'],
  ['absence',`insert into absences(doctor_id,starts_on,ends_on,type) values('${id(10)}','2026-10-05','2026-10-05','zam_late_shift')`,{},'blockingAbsence'],
  ['duplicate',`insert into assignments(roster_slot_id,doctor_id) values('${id(50)}','${id(10)}')`,{},'duplicateAssignment'],
  ['capacity',`insert into assignments(roster_slot_id,doctor_id) values('${id(50)}','${id(11)}')`,{},'slotFull'],
  ['published',`update rosters set phase='published'`,{},'rosterNotEditable'],
  ['locked no reason',`update rosters set phase='locked'`,{},'rosterNotEditable'],
  ['locked whitespace reason',`update rosters set phase='locked'`,{reason:'\t\n'},'rosterNotEditable'],
  ['invalid month',null,{dates:['2026-11-05']},'invalidDate'],
  ['ambiguous',`insert into roster_slots(roster_day_id,role_id,starts_at,ends_at) select roster_day_id,role_id,starts_at,ends_at from roster_slots where id='${id(50)}'`,{},'ambiguousSlot'],
]) await test(`${name} rejected without side effects`,async()=>{
  if(sql) await db.exec(sql); await login(); const before=await count('assignments');
  const r=await apply(options); assert.equal(r.ok,false); assert.ok(codes(r).includes(code),JSON.stringify(r));
  assert.equal(await count('assignments'),before); assert.equal(await count('audit_log'),0);
});
await test('locked reason succeeds and is audited',async()=>{
  await db.exec("update rosters set phase='locked'"); await login();
  assert.equal((await apply({reason:'Reviewed correction'})).ok,true);
  assert.equal((await db.query('select details from audit_log')).rows[0].details.reason,'Reviewed correction');
});
await test('overnight actual Vienna dates block next-day absence and next-day overlap',async()=>{
  await db.exec(`update roster_slots set starts_at='2026-10-05T20:00Z',ends_at='2026-10-06T10:00Z' where id='${id(50)}';
    insert into absences(doctor_id,starts_on,ends_on,type) values('${id(10)}','2026-10-06','2026-10-06','post_duty');`);
  await login(); assert.ok(codes(await apply()).includes('blockingAbsence'));
  await db.exec(`reset role; delete from absences; insert into assignments(roster_slot_id,doctor_id) values('${id(51)}','${id(10)}');`);
  await login(); assert.ok(codes(await apply()).includes('overlappingAssignment'));
});
await test('overlapping proposed targets reject the whole batch',async()=>{
  await db.exec(`update roster_slots set ends_at='2026-10-06T10:00Z' where id='${id(50)}'`);
  await login(); const result=await apply({dates:['2026-10-05','2026-10-06']});
  assert.equal(result.ok,false); assert.ok(result.results.every(r=>r.errors.includes('overlappingAssignment')));
  assert.equal(await count('assignments'),0);
});
await test('open roster succeeds',async()=>{
  await db.exec("update rosters set phase='open_for_selection'"); await login(); assert.equal((await apply()).ok,true);
});
await test('existing overlap rejected; approved SUL/NVB exception succeeds',async()=>{
  await db.exec(`insert into roster_slots(id,roster_day_id,role_id,starts_at,ends_at)
    select '${id(60)}','${id(40)}',id,'2026-10-05T09:00Z','2026-10-05T11:00Z' from roles where code='NVB';
    insert into assignments(roster_slot_id,doctor_id) values('${id(60)}','${id(10)}');`);
  await login(); assert.ok(codes(await apply()).includes('overlappingAssignment'));
  await db.exec(`reset role; delete from roles where code='SUL'; update roles set code='SUL' where id='${id(20)}';`);
  await login(); assert.equal((await apply()).ok,true);
});
await test('same expected version contenders yield one success and one stale',async()=>{
  await login(); const expected=await version();
  const results=await Promise.all([apply({expected,request:70}),apply({expected,request:71,dates:['2026-10-06']})]);
  assert.equal(results.filter(r=>r.ok).length,1); assert.equal(results.filter(r=>r.code==='staleVersion').length,1);
  assert.equal(await count('assignments'),1);
});
await test('idempotent retry returns original receipt even after version advances',async()=>{
  await login(); const expected=await version(); const first=await apply({expected});
  assert.equal(first.ok,true); assert.deepEqual(await apply({expected}),first);
  assert.equal(await count('assignments'),1); assert.equal(await count('audit_log'),1);
  assert.equal((await apply({expected,dates:['2026-10-06']})).code,'idempotencyConflict');
});
await test('legacy changes invalidate snapshot versions and cannot reset stamps',async()=>{
  await login(); const expected=await version(); await db.exec(`reset role;
    insert into assignments(roster_slot_id,doctor_id) values('${id(52)}','${id(11)}');`);
  await login(); assert.equal((await apply({expected})).code,'staleVersion');
  const v=await version(); await db.exec('reset role; update rosters set content_version=1');
  assert.equal(await version(),v+1);
});
await test('zero-row viewer writes cannot advance roster versions',async()=>{
  await db.exec('grant update,delete on public.assignments to authenticated');
  const expected=await version(); await login(3);
  await db.exec("update assignments set state='confirmed'; delete from assignments");
  assert.equal(await version(),expected);
});
await test('audit failure rolls back assignments and version, returns no SQL details',async()=>{
  await db.exec(`create function public.reject_test_audit() returns trigger language plpgsql as $$begin raise exception 'PRIVATE SQL DETAIL'; end$$;
    create trigger reject_test before insert on audit_log for each row execute function public.reject_test_audit();`);
  await login(); const expected=await version(); const r=await apply({expected});
  assert.equal(r.code,'internalError'); assert.equal(JSON.stringify(r).includes('PRIVATE'),false);
  assert.equal(await version(),expected); assert.equal(await count('assignments'),0);
});
if (native) await test('independent PostgreSQL connections race: exactly one commit',async()=>{
  await login(); const expected=await version();
  const clients=await Promise.all([openConnection(),openConnection()]);
  try {
    const responses=await Promise.all(clients.map(async(client,i)=>{
      await client.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:id(1),aal:'aal2'})]);
      await client.query('set role authenticated');
      return (await client.query('select admin_apply_assignments($1,$2,$3,$4,$5::date[],$6,null) as value',
        [id(30),expected,id(10),id(20),[i===0?'2026-10-05':'2026-10-06'],id(80+i)])).rows[0].value;
    }));
    assert.equal(responses.filter(r=>r.ok).length,1);
    assert.equal(responses.filter(r=>r.code==='staleVersion').length,1);
    assert.equal(await count('assignments'),1);
  } finally { await Promise.all(clients.map(c=>c.end())); }
});
console.log(`${tests} isolated PostgreSQL tests passed. ${native?'Independent-connection race passed.':'Contenders are queued in PGlite; real multi-connection lock testing requires --postgres.'}`);
await db.close();
