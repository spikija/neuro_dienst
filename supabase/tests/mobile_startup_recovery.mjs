// Isolated PostgreSQL/WASM test; never connects to a live backend.
// node supabase/tests/mobile_startup_recovery.mjs <PGlite install directory>
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
  create function auth.jwt() returns jsonb language sql stable as
    $$select current_setting('request.jwt.claims',true)::jsonb$$;
  create function auth.uid() returns uuid language sql stable as
    $$select (auth.jwt()->>'sub')::uuid$$;`);
for (const name of (await readdir(path.join(root, 'migrations'))).sort()) {
  await db.exec((await readFile(path.join(root, 'migrations', name), 'utf8'))
    .replace('create extension if not exists pgcrypto;', ''));
}
const repair = await readFile(path.join(root, 'scripts', 'restore_mobile_startup_calendars.sql'), 'utf8');
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;

// Wrong database / missing retained roster must not create anything.
await assert.rejects(db.exec(repair), /November 2026 roster was not found/);
await db.exec('rollback');
assert.equal((await db.query('select count(*)::int n from public.rosters')).rows[0].n, 0);
console.log('PASS missing November aborts the repair');

await db.exec(`
  insert into auth.users(id) values('${id(50)}');
  insert into public.profiles(id,role,display_name)
    values('${id(50)}','doctor','Mobile test user');
  insert into public.doctors(id,first_name,last_name,rank)
    values('${id(1)}','Johanna','Mayrhofer','consultant');
  insert into public.roles(id,code,name) values('${id(2)}','RECOVERY-AMB','Recovery test');
  insert into public.rosters(id,year,month,phase)
    values('${id(3)}',2026,11,'published');
  insert into public.roster_days(id,roster_id,date)
    values('${id(4)}','${id(3)}','2026-11-18');
  insert into public.roster_slots(id,roster_day_id,role_id,starts_at,ends_at)
    values('${id(5)}','${id(4)}','${id(2)}','2026-11-18T08:00Z','2026-11-18T12:00Z');
  insert into public.assignments(id,roster_slot_id,doctor_id,state)
    values('${id(6)}','${id(5)}','${id(1)}','confirmed');
  insert into public.absences(doctor_id,starts_on,ends_on,type)
    values('${id(1)}','2026-11-18','2026-11-18','ef_day');
`);
async function retainedFacts() {
  return (await db.query(`select
    (select jsonb_agg(to_jsonb(d) order by d.id) from public.roster_days d where roster_id='${id(3)}') as days,
    (select jsonb_agg(to_jsonb(s) order by s.id) from public.roster_slots s) as slots,
    (select jsonb_agg(to_jsonb(a) order by a.id) from public.assignments a) as assignments,
    (select jsonb_agg(to_jsonb(a) order by a.id) from public.absences a) as absences,
    (select jsonb_build_object('id',id,'year',year,'month',month,'phase',phase) from public.rosters where id='${id(3)}') as november
  `)).rows;
}
const before = await retainedFacts();
const policies = (await db.query(`select tablename, policyname, roles, cmd, qual, with_check
  from pg_policies where schemaname='public' and tablename in ('rosters','roster_days')
  order by tablename,policyname`)).rows;
await db.exec(repair);
assert.deepEqual((await db.query(`select tablename,rowsecurity from pg_tables
  where schemaname='public' and tablename in ('rosters','roster_days')
  order by tablename`)).rows, [
  {tablename:'roster_days',rowsecurity:true},
  {tablename:'rosters',rowsecurity:true},
]);
assert.deepEqual((await db.query(`select tablename, policyname, roles, cmd, qual, with_check
  from pg_policies where schemaname='public' and tablename in ('rosters','roster_days')
  order by tablename,policyname`)).rows, policies);
await db.query("select set_config('request.jwt.claims',$1,false)", [JSON.stringify({sub:id(50),aal:'aal1'})]);
await db.exec('grant usage on schema auth to authenticated; grant select on public.rosters, public.roster_days to authenticated; set role authenticated');
assert.equal((await db.query('select count(*)::int n from public.rosters')).rows[0].n, 6);
assert.equal((await db.query('select count(*)::int n from public.roster_days')).rows[0].n, 154);
await db.exec('reset role');
console.log('PASS RLS stays enabled, policies are unchanged, authenticated mobile reads still work');
const months = (await db.query(`select r.month, count(d.id)::int days
  from public.rosters r join public.roster_days d on d.roster_id=r.id
  where r.year=2026 and r.month between 6 and 10
  group by r.month order by r.month`)).rows;
assert.deepEqual(months, [
  {month:6,days:30}, {month:7,days:31}, {month:8,days:31},
  {month:9,days:30}, {month:10,days:31},
]);
assert.deepEqual(await retainedFacts(), before);
assert.equal((await db.query(`select count(*)::int n from public.roster_days d
  join public.rosters r on r.id=d.roster_id where r.month between 6 and 10
  and d.is_weekend <> (extract(isodow from d.date) in (6,7))`)).rows[0].n, 0);
assert.deepEqual((await db.query(`select date::text,public_holiday_name from public.roster_days
  where is_public_holiday order by date`)).rows, [
  {date:'2026-06-04', public_holiday_name:'Fronleichnam'},
  {date:'2026-08-15', public_holiday_name:'Mariä Himmelfahrt'},
  {date:'2026-10-26', public_holiday_name:'Nationalfeiertag'},
]);
console.log('PASS 153 calendar days restored, weekends and holidays correct; November, assignments and absences preserved');

const calendars = (await db.query('select id,roster_id,date::text from public.roster_days order by date')).rows;
await db.exec(repair);
assert.deepEqual((await db.query('select id,roster_id,date::text from public.roster_days order by date')).rows, calendars);
assert.deepEqual(await retainedFacts(), before);
console.log('PASS repeating the script preserves all existing records without duplicates');
await db.close();
