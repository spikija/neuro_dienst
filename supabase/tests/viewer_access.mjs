// Run with: node supabase/tests/viewer_access.mjs <test-tools-directory>
// The tools directory must contain @electric-sql/pglite. No live DB is used.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(path.resolve(process.argv[2], 'package.json'));
const { PGlite } = require('@electric-sql/pglite');
const db = new PGlite();
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
await db.exec(`
  create role authenticated;
  create schema auth;
  create table auth.users (id uuid primary key);
  create function auth.jwt() returns jsonb language sql stable as
    $$ select current_setting('request.jwt.claims', true)::jsonb $$;
  create function auth.uid() returns uuid language sql stable as
    $$ select (auth.jwt()->>'sub')::uuid $$;
  grant usage on schema auth to authenticated;
`);
for (const name of (await readdir(path.join(root, 'migrations'))).sort()) {
  let sql = await readFile(path.join(root, 'migrations', name), 'utf8');
  // PostgreSQL provides gen_random_uuid natively; PGlite does not ship pgcrypto.
  sql = sql.replace('create extension if not exists pgcrypto;', '');
  await db.exec(sql);
}
const uid = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
await db.exec(`
  grant usage on schema public to authenticated;
  grant select, insert, update, delete on all tables in schema public to authenticated;
  insert into auth.users values ('${uid(1)}'), ('${uid(2)}'), ('${uid(3)}'), ('${uid(4)}');
  insert into profiles (id, role, display_name) values
    ('${uid(1)}', 'viewer', 'Viewer'), ('${uid(2)}', 'doctor', 'Doctor'),
    ('${uid(3)}', 'admin', 'Admin');
  insert into doctors (id, auth_user_id, first_name, last_name, rank) values
    ('${uid(11)}', '${uid(1)}', 'Linked', 'Viewer', 'resident'),
    ('${uid(12)}', '${uid(2)}', 'Real', 'Doctor', 'resident');
  insert into roles (id, code, name) values ('${uid(20)}', 'TEST', 'Test role');
  insert into role_templates (role_id, start_time, end_time) values ('${uid(20)}', '08:00', '16:00');
  insert into rosters (id, year, month) values ('${uid(30)}', 2098, 1);
  insert into roster_days (id, roster_id, date) values ('${uid(40)}', '${uid(30)}', '2098-01-01');
  insert into roster_slots (id, roster_day_id, role_id, starts_at, ends_at) values
    ('${uid(50)}', '${uid(40)}', '${uid(20)}', '2098-01-01T08:00Z', '2098-01-01T16:00Z'),
    ('${uid(51)}', '${uid(40)}', '${uid(20)}', '2098-01-01T08:00Z', '2098-01-01T16:00Z');
  insert into assignments (roster_slot_id, doctor_id) values ('${uid(50)}', '${uid(11)}');
  insert into absences (doctor_id, starts_on, ends_on, type) values ('${uid(11)}', '2098-02-01', '2098-02-02', 'vacation');
  insert into doctor_enrollment_codes (doctor_id, code_hash) values ('${uid(12)}', 'test');
  insert into audit_log (action, entity_table) values ('fixture', 'roles');
`);
async function login(id, aal = 'aal1') {
  await db.exec('reset role');
  await db.query("select set_config('request.jwt.claims', $1, false)", [JSON.stringify({ sub: uid(id), aal })]);
  await db.exec('set role authenticated');
}
async function denied(sql) {
  await assert.rejects(db.exec(sql), error => error.code === '42501');
}
await login(1, 'aal2');
for (const table of ['doctors', 'roles', 'role_templates', 'rosters', 'roster_days', 'roster_slots', 'assignments']) {
  assert.ok((await db.query(`select * from ${table}`)).rows.length > 0, `viewer reads ${table}`);
}
assert.equal((await db.query('select can_write_app_data() as allowed')).rows[0].allowed, false);
const insertions = {
  profiles: `(id, role, display_name) values ('${uid(4)}', 'admin', 'Escalation')`,
  doctors: `(first_name, last_name, rank) values ('New', 'Doctor', 'resident')`,
  doctor_enrollment_codes: `(doctor_id, code_hash) values ('${uid(11)}', 'new')`,
  roles: `(code, name) values ('VIEWER_WRITE', 'Not allowed')`,
  role_templates: `(role_id, start_time, end_time) values ('${uid(20)}', '09:00', '10:00')`,
  rosters: `(year, month) values (2099, 12)`,
  roster_days: `(roster_id, date) values ('${uid(30)}', '2098-01-02')`,
  roster_slots: `(roster_day_id, role_id, starts_at, ends_at) values ('${uid(40)}', '${uid(20)}', '2098-01-01T09:00Z', '2098-01-01T10:00Z')`,
  assignments: `(roster_slot_id, doctor_id) values ('${uid(51)}', '${uid(11)}')`,
  absences: `(doctor_id, starts_on, ends_on, type) values ('${uid(11)}', '2098-03-01', '2098-03-02', 'vacation')`,
  audit_log: `(action, entity_table) values ('viewer_write', 'roles')`,
};
for (const [table, values] of Object.entries(insertions)) {
  await denied(`insert into ${table} ${values}`);
  assert.equal((await db.query(`update ${table} set id = id returning id`)).rows.length, 0, `${table} update blocked`);
  assert.equal((await db.query(`delete from ${table} returning id`)).rows.length, 0, `${table} delete blocked`);
}
assert.equal((await db.query("update profiles set role = 'admin' where id = $1 returning id", [uid(1)])).rows.length, 0);

// Existing doctor/admin policy behavior remains intact.
await login(2);
await db.exec(`insert into assignments (roster_slot_id, doctor_id) values ('${uid(51)}', '${uid(12)}')`);
await denied(`insert into assignments (roster_slot_id, doctor_id) values ('${uid(51)}', '${uid(11)}')`);
await login(3);
await denied("insert into roles (code, name) values ('ADMIN_TEST', 'Requires MFA')");
await db.exec(`insert into assignments (roster_slot_id, doctor_id) values ('${uid(51)}', '${uid(11)}')`);
await login(3, 'aal2');
await db.exec("insert into roles (code, name) values ('ADMIN_TEST', 'With MFA')");
await login(4);
assert.equal((await db.query('select can_write_app_data() as allowed')).rows[0].allowed, false);
await db.close();
console.log('PASS: viewers read rosters; all 33 table write paths blocked, including linked viewers; doctor/admin permissions preserved.');
