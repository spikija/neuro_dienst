// Isolated PostgreSQL/WASM tests; never connects to a live backend.
// node supabase/tests/admin_absences.mjs <directory containing @electric-sql/pglite>
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFile, readdir} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const require = createRequire(path.resolve(process.argv[2], 'package.json'));
const {PGlite} = require('@electric-sql/pglite');
const db = new PGlite();
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
await db.exec(`create role authenticated; create schema auth;
  create table auth.users(id uuid primary key);
  create function auth.jwt() returns jsonb language sql stable as $$select current_setting('request.jwt.claims',true)::jsonb$$;
  create function auth.uid() returns uuid language sql stable as $$select (auth.jwt()->>'sub')::uuid$$;
  grant usage on schema auth to authenticated;`);
for (const name of (await readdir(path.join(root, 'migrations'))).sort()) {
  await db.exec((await readFile(path.join(root, 'migrations', name), 'utf8'))
    .replace('create extension if not exists pgcrypto;', ''));
}
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
await db.exec(`grant usage on schema public to authenticated;
  grant select on public.rosters, public.absences, public.assignments, public.audit_log to authenticated;
  insert into auth.users values ('${id(1)}'),('${id(2)}'),('${id(3)}');
  insert into public.profiles(id,role,display_name) values
    ('${id(1)}','admin','Admin'),('${id(2)}','doctor','Doctor'),('${id(3)}','viewer','Viewer');
  insert into public.doctors(id,first_name,last_name,rank) values
    ('${id(10)}','Johanna','Mayrhofer','consultant'),('${id(11)}','Other','Physician','resident');
  insert into public.rosters(id,year,month) values ('${id(30)}',2026,11);
  insert into public.absences(id,doctor_id,starts_on,ends_on,type,note,created_by) values
    ('${id(40)}','${id(10)}','2026-11-17','2026-11-19','ef_day','keep this note','${id(2)}'),
    ('${id(41)}','${id(10)}','2026-11-18','2026-11-18','vacation','unrelated',null),
    ('${id(42)}','${id(11)}','2026-11-18','2026-11-18','ef_day','other physician',null);`);
async function login(user = 1, aal = 'aal2') {
  await db.exec('reset role');
  await db.query("select set_config('request.jwt.claims',$1,false)", [JSON.stringify({sub:user ? id(user):null,aal})]);
  await db.exec('set role authenticated');
}
const version = async () => Number((await db.query(`select content_version from public.rosters where id='${id(30)}'`)).rows[0].content_version);
const remove = async ({expected, request = 80, date = '2026-11-18', physician = 10, type = 'vacation'} = {}) =>
  (await db.query('select public.admin_remove_absence_day($1,$2,$3,$4,$5,$6) value',
    [id(30), expected ?? await version(), id(physician), date, type, id(request)])).rows[0].value;
let tests = 0;
async function test(name, run) {
  await db.exec('reset role; begin');
  try { await run(); tests++; console.log(`PASS ${name}`); }
  finally { await db.exec('rollback; reset role'); }
}
await db.exec(`delete from public.absences where id is not null;
  insert into public.absences(doctor_id,starts_on,ends_on,type,note,created_by,created_at)
  select d.id,'2026-11-17','2026-11-19',t,'retained metadata','${id(2)}','2026-10-01T10:00Z'
  from public.doctors d cross join unnest(enum_range(null::public.availability_type)) t;
  insert into public.roles(id,code,name) values ('${id(50)}','TEST-ABS','Absence test');
  insert into public.roster_days(id,roster_id,date) values ('${id(60)}','${id(30)}','2026-11-18');
  insert into public.roster_slots(id,roster_day_id,role_id,starts_at,ends_at)
  values ('${id(61)}','${id(60)}','${id(50)}','2026-11-18T08:00Z','2026-11-18T12:00Z');
  insert into public.assignments(id,roster_slot_id,doctor_id,state)
  values ('${id(62)}','${id(61)}','${id(10)}','confirmed');`);
const types = (await db.query('select unnest(enum_range(null::public.availability_type))::text as type')).rows.map(r=>r.type);
assert.equal(types.length,12);
for (const [user, aal, code] of [[2,'aal2','unauthorized'],[3,'aal2','unauthorized'],[0,'aal2','unauthorized'],[1,'aal1','mfaRequired']]) {
  await test(`rejects user ${user}, ${aal}`, async () => {
    const v = await version();
    await login(user, aal);
    assert.equal((await remove({expected:v})).code, code);
  });
}
for (const type of types) {
  await test(`${type}: removes only selected date/type/physician; retains all other absences and assignments`, async () => {
    await login();
    const v = await version();
    const others = async () => (await db.query(`select id,doctor_id,starts_on::text,ends_on::text,type::text,note
      from public.absences where not(doctor_id=$1 and type::text=$2) order by id`, [id(10),type])).rows;
    const original = await others();
    const result = await remove({expected:v,type});
    assert.equal(result.ok,true);
    assert.equal(result.type,type);
    assert.ok(Number(result.contentVersion)>v);
    const retained = (await db.query(`select starts_on::text,ends_on::text,note,created_by,created_at::text
      from public.absences where doctor_id=$1 and type::text=$2 order by starts_on`,[id(10),type])).rows;
    assert.deepEqual(retained.map(r=>[r.starts_on,r.ends_on]),[['2026-11-17','2026-11-17'],['2026-11-19','2026-11-19']]);
    assert.ok(retained.every(r=>r.note==='retained metadata' && r.created_by===id(2) && new Date(r.created_at).toISOString()==='2026-10-01T10:00:00.000Z'));
    assert.deepEqual(await others(),original);
    assert.equal((await db.query(`select count(*)::int n from public.assignments where id='${id(62)}'`)).rows[0].n,1);
    const audit = (await db.query("select details from public.audit_log where action='admin_remove_absence_day'")).rows;
    assert.equal(audit.length,1);
    assert.equal(audit[0].details.type,type);
    assert.deepEqual(await remove({expected:v,type}),result);
    assert.equal((await remove({expected:v,type:types.find(t=>t!==type)})).code,'idempotencyConflict');
  });
}
await test('invalid types, stale snapshots, wrong month and missing entries make no changes',async()=>{
  await login();
  const v=await version();
  assert.equal((await remove({expected:v-1})).code,'staleVersion');
  assert.equal((await remove({type:'invalid_type'})).code,'invalidRequest');
  assert.equal((await remove({type:null})).code,'invalidRequest');
  assert.equal((await remove({date:'2026-12-18'})).code,'invalidRequest');
  assert.equal((await remove({date:'2026-11-20'})).code,'noAbsence');
  assert.equal(await version(),v);
});
await test('duplicate overlapping entries of the selected type are all removed for that date',async()=>{
  await db.exec(`insert into public.absences(doctor_id,starts_on,ends_on,type)
    values('${id(10)}','2026-11-18','2026-11-18','vacation')`);
  await login();
  assert.equal((await remove()).ok,true);
  assert.equal((await db.query(`select count(*)::int n from public.absences where doctor_id='${id(10)}'
    and type='vacation' and starts_on<='2026-11-18' and ends_on>='2026-11-18'`)).rows[0].n,0);
});
await test('removing a 24-hour marker does not implicitly remove the following post-duty date',async()=>{
  await db.exec(`insert into public.absences(doctor_id,starts_on,ends_on,type)
    values('${id(10)}','2026-11-30','2026-11-30','duty_24'),
    ('${id(10)}','2026-12-01','2026-12-01','post_duty')`);
  await login();
  assert.equal((await remove({date:'2026-11-30',type:'duty_24'})).ok,true);
  assert.equal((await db.query(`select count(*)::int n from public.absences where doctor_id='${id(10)}'
    and type='post_duty' and starts_on='2026-12-01'`)).rows[0].n,1);
});
for (const table of ['absences','audit_log']) {
  await test(`a ${table} insert failure rolls back the entire removal and version`,async()=>{
    await db.exec(`create function public.test_reject_insert() returns trigger language plpgsql as $$begin
      raise exception 'injected failure'; end$$;
      create trigger test_reject_insert before insert on public.${table}
      for each row execute function public.test_reject_insert();`);
    await login();
    const v=await version();
    await db.exec('savepoint failed_mutation');
    await assert.rejects(remove());
    await db.exec('rollback to savepoint failed_mutation');
    assert.equal(await version(),v);
    assert.equal((await db.query(`select count(*)::int n from public.absences where doctor_id='${id(10)}'
      and type='vacation' and starts_on='2026-11-17' and ends_on='2026-11-19'`)).rows[0].n,1);
  });
}
console.log(`${tests} absence database tests passed`);
await db.close();
