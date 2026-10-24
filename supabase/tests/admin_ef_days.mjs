// Isolated PostgreSQL/WASM tests; never connects to a live backend.
// node supabase/tests/admin_ef_days.mjs <directory containing @electric-sql/pglite>
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
  grant select on public.rosters, public.absences, public.audit_log to authenticated;
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
const remove = async ({expected, request = 80, date = '2026-11-18', physician = 10} = {}) =>
  (await db.query('select public.admin_remove_ef_day($1,$2,$3,$4,$5) value',
    [id(30), expected ?? await version(), id(physician), date, id(request)])).rows[0].value;
let tests = 0;
async function test(name, run) {
  await db.exec('reset role; begin');
  try { await run(); tests++; console.log(`PASS ${name}`); }
  finally { await db.exec('rollback; reset role'); }
}
for (const [user, aal, code] of [[2,'aal2','unauthorized'],[3,'aal2','unauthorized'],[0,'aal2','unauthorized'],[1,'aal1','mfaRequired']]) {
  await test(`rejects user ${user}, ${aal}`, async () => {
    const v = await version();
    await login(user, aal);
    assert.equal((await remove({expected:v})).code, code);
  });
}
await test('removes only 18 November, retaining adjacent EF dates, metadata and unrelated entries', async () => {
  await login();
  const v = await version();
  const result = await remove({expected:v});
  assert.equal(result.ok, true);
  assert.equal(result.date, '2026-11-18');
  assert.ok(Number(result.contentVersion) > v);
  const rows = (await db.query(`select starts_on::text, ends_on::text, note, created_by
    from public.absences where doctor_id='${id(10)}' and type='ef_day' order by starts_on`)).rows;
  assert.deepEqual(rows.map(r => [r.starts_on,r.ends_on]), [['2026-11-17','2026-11-17'],['2026-11-19','2026-11-19']]);
  assert.ok(rows.every(r => r.note === 'keep this note' && r.created_by === id(2)));
  assert.equal((await db.query(`select count(*)::int n from public.absences where id in ('${id(41)}','${id(42)}')`)).rows[0].n, 2);
  assert.equal((await db.query("select count(*)::int n from public.audit_log where action='admin_remove_ef_day'")).rows[0].n, 1);
  assert.deepEqual(await remove({expected:v}), result);
  assert.equal((await remove({expected:v, date:'2026-11-17'})).code, 'idempotencyConflict');
});
await test('single-day entry is deleted and duplicate covering EF records cannot survive', async () => {
  await db.exec(`insert into public.absences(doctor_id,starts_on,ends_on,type) values
    ('${id(10)}','2026-11-18','2026-11-18','ef_day')`);
  await login();
  assert.equal((await remove()).ok, true);
  assert.equal((await db.query(`select count(*)::int n from public.absences where doctor_id='${id(10)}'
    and type='ef_day' and starts_on<='2026-11-18' and ends_on>='2026-11-18'`)).rows[0].n, 0);
});
await test('stale snapshots, dates outside the month and missing EF entries cannot write', async () => {
  await login();
  const v = await version();
  assert.equal((await remove({expected:v-1})).code, 'staleVersion');
  assert.equal((await remove({date:'2026-12-18'})).code, 'invalidRequest');
  assert.equal((await remove({date:'2026-11-20'})).code, 'noEfDay');
  assert.equal(await version(), v);
});
await test('splitting is atomic if a retained period cannot be inserted', async () => {
  await db.exec(`create function public.test_reject_ef_insert() returns trigger language plpgsql as $$begin
    raise exception 'injected insert failure'; end$$;
    create trigger test_reject_ef_insert before insert on public.absences
    for each row execute function public.test_reject_ef_insert();`);
  await login();
  const v = await version();
  await db.exec('savepoint failed_mutation');
  await assert.rejects(remove());
  await db.exec('rollback to savepoint failed_mutation');
  assert.equal(await version(), v);
  assert.equal((await db.query(`select count(*)::int n from public.absences where id='${id(40)}'`)).rows[0].n, 1);
});
console.log(`${tests} EF day database tests passed`);
await db.close();
