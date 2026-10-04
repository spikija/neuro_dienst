// Executes the real Edge Function handler with mocked Supabase calls, no emails.
// Run with Node 24+: node supabase/tests/viewer_invitation.mjs
import assert from 'node:assert/strict';
import { stripTypeScriptTypes } from 'node:module';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

const source = (await readFile(new URL('../functions/invite-doctor/index.ts', import.meta.url), 'utf8'))
  .replace("import { createClient } from 'npm:@supabase/supabase-js@2'", '');
const compiled = stripTypeScriptTypes(source);

async function invite(body, { callerRole = 'admin', aal = 'aal2', mailError = null } = {}) {
  const calls = [];
  let handler;
  const createClient = () => ({
    auth: {
      getUser: async () => ({ data: { user: { id: 'caller' } }, error: null }),
      admin: {
        createUser: async payload => {
          calls.push({ operation: 'createUser', payload });
          return { data: { user: { id: 'new-user' } }, error: null };
        },
        deleteUser: async id => { calls.push({ operation: 'deleteUser', id }); return { error: null }; },
      },
      resetPasswordForEmail: async email => {
        calls.push({ operation: 'email', email });
        return { error: mailError };
      },
    },
    from: table => {
      calls.push({ operation: 'from', table });
      const query = {
        select: () => query, eq: () => query, order: () => query, limit: () => query,
        insert: payload => { calls.push({ operation: 'insert', table, payload }); return query; },
        delete: () => { calls.push({ operation: 'delete', table }); return query; },
        maybeSingle: async () => ({ data: table === 'profiles' ? { role: callerRole } : { print_order: 1 }, error: null }),
        single: async () => ({ data: { id: 'new-doctor' }, error: null }),
        then: resolve => resolve({ data: null, error: null }),
      };
      return query;
    },
  });
  vm.runInNewContext(compiled, {
    createClient, Request, Response, atob,
    Deno: { env: { get: key => `test-${key}` }, serve: fn => { handler = fn; } },
  });
  const token = `header.${Buffer.from(JSON.stringify({ aal })).toString('base64url')}.signature`;
  const response = await handler(new Request('https://test.invalid/invite-doctor', {
    method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'viewer@example.invalid', firstName: 'Test', lastName: 'User', preferredLanguage: 'en', ...body }),
  }));
  return { status: response.status, data: await response.json(), calls };
}

const viewer = await invite({ accountRole: 'viewer' });
assert.equal(viewer.status, 201);
assert.equal(viewer.data.accountRole, 'viewer');
assert.equal(viewer.data.doctorId, null);
assert.equal(viewer.calls.find(c => c.operation === 'insert' && c.table === 'profiles').payload.role, 'viewer');
assert.equal(viewer.calls.some(c => c.table === 'doctors'), false);
assert.equal(viewer.calls.filter(c => c.operation === 'email').length, 1);

const doctor = await invite({ rank: 'resident' });
assert.equal(doctor.status, 201);
assert.equal(doctor.data.accountRole, 'doctor');
assert.ok(doctor.calls.some(c => c.operation === 'insert' && c.table === 'doctors'));

for (const role of ['admin', '', 'unknown']) {
  const rejected = await invite({ accountRole: role });
  assert.equal(rejected.status, 400);
  assert.equal(rejected.calls.some(c => c.operation === 'createUser'), false);
}
for (const callerRole of ['viewer', 'doctor']) {
  const rejected = await invite({ accountRole: 'viewer' }, { callerRole });
  assert.equal(rejected.status, 403);
  assert.equal(rejected.calls.some(c => c.operation === 'createUser'), false);
}
const noMfa = await invite({ accountRole: 'viewer' }, { aal: 'aal1' });
assert.equal(noMfa.status, 403);
assert.equal(noMfa.calls.some(c => c.operation === 'createUser'), false);
const failedMail = await invite({ accountRole: 'viewer' }, { mailError: new Error('mail failed') });
assert.equal(failedMail.status, 500);
assert.ok(failedMail.calls.some(c => c.operation === 'deleteUser' && c.id === 'new-user'));
console.log('PASS: viewer provisioning, unchanged doctor flow, privileged-role rejection, admin/MFA gate, and failed-email cleanup.');
