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
if (safeupdate) await db.exec('alter function public.admin_manage_directory(text,uuid,timestamptz,jsonb,uuid) set safeupdate.enabled=on');
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
await db.exec(`grant usage on schema public to authenticated;
grant select,insert,update,delete on all tables in schema public to authenticated;
insert into auth.users(id,email) values ('${id(1)}','admin@example.invalid'),('${id(2)}','viewer@example.invalid'),('${id(3)}','doctor@example.invalid');
insert into profiles(id,role,display_name) values ('${id(1)}','admin','Admin'),('${id(2)}','viewer','Viewer'),('${id(3)}','doctor','Doctor');
insert into doctors(id,first_name,last_name,rank,auth_user_id) values ('${id(10)}','Historical','Physician','consultant','${id(3)}'),('${id(11)}','Linked','Viewer','resident','${id(2)}'),('${id(12)}','Unused','Physician','resident',null);
insert into absences(doctor_id,starts_on,ends_on,type) values ('${id(10)}','2025-01-01','2025-01-02','vacation');
insert into rosters(year,month) values(2025,1);`);
async function login(user=1,aal='aal2') {
 await db.exec('reset role');
 await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:id(user),aal})]);
 await db.exec('set role authenticated');
}
const directory = async kind => (await db.query('select admin_directory($1) value',[kind])).rows[0].value;
let request=100;
async function change(kind, row, changes, token=id(++request)) {
 return (await db.query('select admin_manage_directory($1,$2,$3,$4::jsonb,$5) value',[kind,row.id,row.updated_at,JSON.stringify(changes),token])).rows[0].value;
}
for (const [user,aal] of [[1,'aal1'],[2,'aal2'],[3,'aal2']]) {
 await login(user,aal);
 await assert.rejects(directory('physicians'),e=>e.code==='42501');
 assert.ok((await change('physicians',{id:id(10),updated_at:'2026-01-01'},{})).error);
}
await login();
const physicians = await directory('physicians');
assert.deepEqual(physicians.map(d=>d.id),[id(10),id(12)]);
assert.equal(physicians[0].email,'doctor@example.invalid');
const historic = physicians[0];
assert.equal((await change('physicians',historic,{delete:true})).error,'physicianHasDependencies');
assert.equal((await db.query('select count(*)::int n from absences')).rows[0].n,1);
const token=id(++request);
assert.equal((await change('physicians',historic,{is_active:false},token)).success,true);
assert.equal((await change('physicians',historic,{is_active:false},token)).success,true);
assert.equal((await change('physicians',historic,{is_active:true},token)).error,'idempotencyConflict');
assert.equal((await change('physicians',historic,{first_name:'Stale'})).error,'staleVersion');
assert.equal((await directory('physicians'))[0].is_active,false);
assert.equal((await db.query('select count(*)::int n from absences')).rows[0].n,1);
assert.equal((await change('physicians',physicians[1],{delete:true})).success,true);
assert.equal((await directory('physicians')).length,1);
await assert.rejects(db.query('delete from doctors where id=$1',[id(10)]),e=>e.code==='23503');
const viewer = (await directory('viewers'))[0];
assert.equal((await change('viewers',viewer,{role:'admin'})).error,'invalidField');
assert.equal((await change('viewers',viewer,{access_revoked:true})).success,true);
await login(2);
for (const table of ['profiles','doctors','roles','rosters','assignments','absences']) {
 assert.equal((await db.query(`select count(*)::int n from ${table}`)).rows[0].n,0,`revoked JWT blocked on ${table}`);
}
await login();
const revoked=(await directory('viewers'))[0];
assert.equal(revoked.access_revoked,true);
assert.equal((await change('viewers',revoked,{display_name:'Updated viewer',access_revoked:false})).success,true);
await login(2);
assert.equal((await db.query('select count(*)::int n from rosters')).rows[0].n,1);
await assert.rejects(db.exec('insert into rosters(year,month) values(2025,2)'),e=>e.code==='42501');
await db.exec('reset role');
await db.exec(`insert into doctors(id,first_name,last_name,rank) values('${id(13)}','Enrolled','Physician','resident');
 insert into doctor_enrollment_codes(doctor_id,code_hash) values('${id(13)}','fixture');
 insert into roles(id,code,name) values('${id(20)}','TEST','Test');
 insert into roster_days(id,roster_id,date) select '${id(21)}',id,'2025-01-01' from rosters where year=2025 and month=1;
 insert into roster_slots(id,roster_day_id,role_id,starts_at,ends_at) values('${id(22)}','${id(21)}','${id(20)}','2025-01-01T08:00Z','2025-01-01T16:00Z');
 insert into assignments(roster_slot_id,doctor_id) values('${id(22)}','${id(10)}');`);
await login();
const refreshed=await directory('physicians');
assert.equal((await change('physicians',refreshed.find(p=>p.id===id(13)),{delete:true})).error,'physicianHasDependencies');
assert.equal((await change('physicians',refreshed.find(p=>p.id===id(10)),{delete:true})).error,'physicianHasDependencies');
assert.equal((await db.query('select count(*)::int n from assignments')).rows[0].n,1);
await db.exec(`reset role; create function public.test_audit_failure() returns trigger language plpgsql as $$begin raise exception 'test audit failure'; end$$;
create trigger test_audit_failure before insert on public.audit_log for each row execute function public.test_audit_failure();`);
await login();
const before=(await directory('viewers'))[0];
await assert.rejects(change('viewers',before,{access_revoked:true}));
assert.equal((await directory('viewers'))[0].access_revoked,false,'audit failure rolls back revocation');
await db.close();
console.log('PASS directory: admin+AAL2, viewer separation, archive/history, dependency-safe deletion, versions/idempotency, revoke existing JWT, restore read-only access.');
