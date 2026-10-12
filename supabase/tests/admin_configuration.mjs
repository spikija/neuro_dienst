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


await db.exec('alter table auth.users add column email text');
const id=n=>`10000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
await db.exec(`grant usage on schema public to authenticated; grant select,insert,update,delete on all tables in schema public to authenticated;
 insert into auth.users(id) values('${id(1)}'),('${id(2)}'),('${id(3)}'),('${id(4)}'),('${id(5)}');
 insert into profiles(id,role,display_name) values('${id(1)}','admin','Admin'),('${id(2)}','doctor','Unused'),('${id(3)}','viewer','Viewer'),('${id(4)}','doctor','History'),('${id(5)}','doctor','Audit');
 insert into doctors(id,auth_user_id,first_name,last_name,rank) values('${id(20)}','${id(2)}','Unused','Test','resident'),('${id(21)}','${id(4)}','Historical','Test','resident'),('${id(22)}','${id(5)}','Audit','Test','resident');
 insert into absences(doctor_id,starts_on,ends_on,type) values('${id(21)}','2026-01-01','2026-01-02','vacation');
 insert into audit_log(action,entity_table,details) values('old_assignment','assignments','{"physicianId":"${id(22)}"}');
 insert into doctors(id,first_name,last_name,rank) values('${id(23)}','Assigned','Test','resident');
 insert into rosters(id,year,month) values('${id(70)}',2026,1);
 insert into roster_days(id,roster_id,date) values('${id(71)}','${id(70)}','2026-01-05');
 insert into roster_slots(id,roster_day_id,role_id,starts_at,ends_at) select '${id(72)}','${id(71)}',id,'2026-01-05T07:00Z','2026-01-05T15:00Z' from roles where code='SUL';
 insert into assignments(roster_slot_id,doctor_id) values('${id(72)}','${id(23)}');
 create table auth.identities(id uuid primary key,user_id uuid references auth.users(id) on delete cascade);
 insert into auth.identities values('${id(90)}','${id(2)}');`);
async function login(user=1,aal='aal2'){await db.exec('reset role');await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:id(user),aal})]);await db.exec('set role authenticated');}
if(safeupdate)await db.exec('alter function public.admin_delete_account(text,uuid,timestamptz,boolean,uuid) set safeupdate.enabled=on; alter function public.admin_save_configuration(text,uuid,timestamptz,jsonb,boolean,uuid) set safeupdate.enabled=on');
const cfg=async()=>(await db.query('select admin_configuration() v')).rows[0].v;
let seq=100;
const save=async(kind,row,values,del=false,token=id(++seq))=>(await db.query('select admin_save_configuration($1,$2,$3,$4::jsonb,$5,$6) v',[kind,row.id,row.updated_at??null,JSON.stringify(values),del,token])).rows[0].v;
const remove=async(kind,row,ack=true,token=id(++seq))=>(await db.query('select admin_delete_account($1,$2,$3,$4,$5) v',[kind,row.id,row.updated_at,ack,token])).rows[0].v;
const rows=async kind=>(await db.query('select admin_directory($1) v',[kind])).rows[0].v;
await login();
const unused=(await rows('physicians')).find(r=>r.id===id(20));
for(const [user,aal] of [[1,'aal1'],[2,'aal2'],[3,'aal2']]){
 await login(user,aal);await assert.rejects(cfg(),e=>e.code==='42501');
 assert.ok((await remove('physicians',unused)).error);
 assert.ok((await save('roles',{id:id(40)},{code:'bad'})).error);
}
await login();
assert.equal((await remove('physicians',unused,false)).error,'invalidRequest');
for(const doc of (await rows('physicians')).filter(r=>r.id!==id(20))) assert.equal((await remove('physicians',doc)).error,'accountHasDependencies');
assert.equal((await db.query('select count(*)::int n from assignments')).rows[0].n,1,'historical assignment retained');
const deletionToken=id(++seq);
assert.equal((await remove('physicians',unused,true,deletionToken)).success,true);
assert.equal((await remove('physicians',unused,true,deletionToken)).success,true);
await db.exec('reset role');
for(const table of ['auth.users','profiles'])assert.equal((await db.query(`select count(*)::int n from ${table} where id=$1`,[id(2)])).rows[0].n,0);
assert.equal((await db.query('select count(*)::int n from auth.identities')).rows[0].n,0);
assert.equal((await db.query("select count(*)::int n from audit_log where action='admin_delete_account'")).rows[0].n,1);
await login(); const viewer=(await rows('viewers'))[0];
assert.equal((await remove('viewers',viewer)).success,true);
await login(3);assert.equal((await db.query('select count(*)::int n from roles')).rows[0].n,0,'deleted JWT denied reads');
await login();
const r={id:id(40)};
const values={code:'CUSTOM-Clinic-17',name:'Custom clinic',is_active:true,allowed_ranks:['resident'],required_capabilities:[],max_doctors:2,print_in_report:true,display_order:99};
assert.equal((await save('roles',r,values)).success,true);
let role=(await cfg()).roles.find(r=>r.id===id(40));
// Palette values persist by role ID; invalid RGB/tokens roll back without changing configuration.
assert.equal((await save('roles',role,{color_key:'teal'})).success,true);
role=(await cfg()).roles.find(v=>v.id===r.id);
assert.equal(role.color_key,'teal');
assert.equal((await save('roles',role,{color_key:'#ff0000'})).error,'invalidRequest');
assert.equal((await cfg()).roles.find(v=>v.id===r.id).color_key,'teal');
assert.ok((await db.query("select details from audit_log where action='admin_configuration_change' and entity_id=$1",[r.id])).rows.some(v=>v.details.values?.color_key==='teal'));
const editToken=id(++seq);
assert.equal((await save('roles',role,{name:'Renamed custom clinic'},false,editToken)).success,true);
assert.equal((await save('roles',role,{name:'Renamed custom clinic'},false,editToken)).success,true);
assert.equal((await save('roles',role,{name:'Stale'})).error,'staleVersion');
role=(await cfg()).roles.find(r=>r.id===id(40));
let template={id:id(41)};
const tv={role_id:role.id,weekday_rule:'every_weekday',monthly_day:null,weekdays:[1,6],start_time:'08:00',end_time:'16:00',capacity:3,is_active:true};
assert.equal((await save('templates',template,tv)).success,true);
const preview=async()=>(await db.query('select admin_preview_generation(2027,6) v')).rows[0].v;
let plan=await preview();
assert.ok(plan.plan.slots.some(s=>s.roleId===role.id&&s.capacity===3&&new Date(s.startsAt).getUTCHours()===6));
assert.equal(plan.plan.slots.filter(s=>s.roleId===role.id).length,8,'Mondays and Saturdays in June 2027');
assert.ok(plan.plan.templates.some(t=>t.code==='SUL'),'existing neurology generation preserved');
assert.equal((await save('roles',role,{},true)).error,'configurationHasDependencies');
template=(await cfg()).templates.find(t=>t.id===id(41));
assert.equal((await save('templates',template,{is_active:false})).success,true);
assert.equal((await preview()).plan.slots.filter(s=>s.roleId===role.id).length,0);
template=(await cfg()).templates.find(t=>t.id===id(41));
assert.equal((await save('templates',template,{is_active:true,weekday_rule:'monthly_day',monthly_day:15,weekdays:null})).success,true);
plan=await preview();assert.equal(plan.plan.slots.filter(s=>s.roleId===role.id).length,1);
assert.equal((await save('roles',role,{is_active:false})).success,true);
assert.equal((await preview()).plan.slots.filter(s=>s.roleId===role.id).length,0);
role=(await cfg()).roles.find(r=>r.id===id(40));
assert.equal((await save('roles',role,{is_active:true})).success,true);
role=(await cfg()).roles.find(r=>r.id===id(40));
plan=await preview();
const generated=(await db.query('select admin_apply_generation(2027,6,null,null,$1,$2) v',[plan.token,id(++seq)])).rows[0].v;
assert.equal(generated.ok,true);
template=(await cfg()).templates.find(t=>t.id===id(41));
assert.equal((await save('templates',template,{},true)).success,true);
assert.equal((await save('roles',role,{},true)).error,'configurationHasDependencies','historical slots retain role');
const unreferenced={id:id(50)};
assert.equal((await save('roles',unreferenced,{...values,code:'Unused arbitrary'})).success,true);
assert.equal((await save('roles',(await cfg()).roles.find(r=>r.id===id(50)),{},true)).success,true);
// Audit failures must roll back Auth, profile, doctor and configuration writes.
await db.exec(`reset role; insert into auth.users(id) values('${id(6)}');
 insert into profiles(id,role,display_name) values('${id(6)}','viewer','Rollback');
 create function public.test_atomic_audit() returns trigger language plpgsql as $$begin raise exception 'audit unavailable'; end$$;
 create trigger test_atomic_audit before insert on public.audit_log for each row execute function public.test_atomic_audit();`);
await login(); const rollback=(await rows('viewers'))[0];await assert.rejects(remove('viewers',rollback));
await db.exec('reset role');assert.equal((await db.query('select count(*)::int n from auth.users where id=$1',[id(6)])).rows[0].n,1);
assert.equal((await db.query('select count(*)::int n from profiles where id=$1',[id(6)])).rows[0].n,1);
await db.close();
console.log('PASS configuration/account lifecycle: authorization, full Auth/profile deletion, history/audit guards, rollback, stale versions, retries, arbitrary roles, template recurrence/capacity/activation, generic+neurology generation, role dependency deletion.');
