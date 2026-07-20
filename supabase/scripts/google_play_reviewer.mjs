#!/usr/bin/env node

const action = process.argv[2];
const supportedActions = new Set([
  'create',
  'verify',
  'reset-password',
  'delete',
]);

if (!supportedActions.has(action)) {
  fail(
    'Usage: node supabase/scripts/google_play_reviewer.mjs ' +
      '<create|verify|reset-password|delete>',
  );
}

const supabaseUrl = requiredEnvironment('SUPABASE_URL').replace(/\/$/, '');
const serviceRoleKey = requiredEnvironment('SUPABASE_SERVICE_ROLE_KEY');
const reviewerEmail = requiredEnvironment(
  'GOOGLE_PLAY_REVIEWER_EMAIL',
).toLowerCase();
const reviewerPassword =
  action === 'delete'
    ? process.env.GOOGLE_PLAY_REVIEWER_PASSWORD?.trim()
    : requiredEnvironment('GOOGLE_PLAY_REVIEWER_PASSWORD');
const publishableKey = process.env.SUPABASE_PUBLISHABLE_KEY?.trim();

let configurationValid = true;
try {
  validateConfiguration();
} catch (error) {
  reportFailure(error instanceof Error ? error.message : String(error));
  configurationValid = false;
}

if (configurationValid) {
  try {
    switch (action) {
      case 'create':
        await createReviewer();
        break;
      case 'verify':
        await verifyReviewer();
        break;
      case 'reset-password':
        await resetReviewerPassword();
        break;
      case 'delete':
        await deleteReviewer();
        break;
    }
  } catch (error) {
    reportFailure(error instanceof Error ? error.message : String(error));
  }
}

async function createReviewer() {
  const existingUser = await findUserByEmail(reviewerEmail);
  if (existingUser) {
    throw new Error(
      'A Supabase Auth user with the reviewer email already exists. ' +
        'No data was changed. Use reset-password or delete explicitly.',
    );
  }

  const user = await adminRequest('/auth/v1/admin/users', {
    method: 'POST',
    body: {
      email: reviewerEmail,
      password: reviewerPassword,
      email_confirm: true,
      user_metadata: {
        display_name: 'Google Reviewer',
        account_purpose: 'google_play_review',
      },
    },
  });

  if (!user?.id) {
    throw new Error('Supabase created no usable Auth user.');
  }

  let doctorCreated = false;
  try {
    await serviceRestRequest('/rest/v1/profiles?on_conflict=id', {
      method: 'POST',
      prefer: 'resolution=merge-duplicates,return=representation',
      body: {
        id: user.id,
        role: 'doctor',
        display_name: 'Google Reviewer',
        preferred_language: 'en',
      },
    });

    const highestRows = await serviceRestRequest(
      '/rest/v1/doctors?select=print_order&order=print_order.desc&limit=1',
    );
    const nextPrintOrder = Number(highestRows?.[0]?.print_order ?? 0) + 1;

    await serviceRestRequest(
      '/rest/v1/doctors?on_conflict=auth_user_id',
      {
        method: 'POST',
        prefer: 'resolution=merge-duplicates,return=representation',
        body: {
          auth_user_id: user.id,
          first_name: 'Google',
          last_name: 'Reviewer',
          rank: 'head',
          capabilities: [
            'can_lead',
            'can_work_outpatient_clinic',
            'can_do_neurosonography',
            'can_do_night_duty',
            'can_supervise',
          ],
          is_active: true,
          print_order: nextPrintOrder,
        },
      },
    );
    doctorCreated = true;
  } catch (error) {
    await rollbackCreatedReviewer(user.id, doctorCreated);
    throw new Error(
      `Reviewer provisioning failed and was rolled back: ${safeMessage(error)}`,
    );
  }

  console.log('Google Play reviewer account created successfully.');
  console.log('Email is confirmed; profile role is doctor; MFA is not enrolled.');
  console.log('Run the verify command before entering credentials in Play Console.');
}

async function verifyReviewer() {
  const tokenResponse = await publicRequest(
    '/auth/v1/token?grant_type=password',
    {
      method: 'POST',
      body: { email: reviewerEmail, password: reviewerPassword },
    },
  );
  const accessToken = tokenResponse?.access_token;
  const userId = tokenResponse?.user?.id;
  if (!accessToken || !userId) {
    throw new Error('Password login returned no valid session.');
  }

  try {
    const profiles = await userRestRequest(
      `/rest/v1/profiles?select=id,role,display_name&id=eq.${encodeURIComponent(userId)}`,
      accessToken,
    );
    if (
      profiles?.length !== 1 ||
      profiles[0].role !== 'doctor' ||
      profiles[0].display_name !== 'Google Reviewer'
    ) {
      throw new Error('Reviewer profile is missing or has the wrong role/name.');
    }

    const doctors = await userRestRequest(
      `/rest/v1/doctors?select=id,auth_user_id,is_active&auth_user_id=eq.${encodeURIComponent(userId)}`,
      accessToken,
    );
    const doctor = doctors?.[0];
    if (!doctor?.id || doctor.is_active !== true) {
      throw new Error('Active doctor record is missing or not linked to Auth.');
    }

    const existingAssignments = await userRestRequest(
      `/rest/v1/assignments?select=roster_slot_id&doctor_id=eq.${encodeURIComponent(doctor.id)}`,
      accessToken,
    );
    const occupiedSlotIds = new Set(
      (existingAssignments ?? []).map((row) => row.roster_slot_id),
    );
    const slots = await userRestRequest(
      '/rest/v1/roster_slots?select=id&order=starts_at.desc&limit=100',
      accessToken,
    );
    const testSlot = (slots ?? []).find((slot) => !occupiedSlotIds.has(slot.id));
    if (!testSlot) {
      throw new Error(
        'Password login and linked profile passed, but no free roster slot ' +
          'is available for the create/remove RLS test. Generate a fictional ' +
          'test roster, then run verify again.',
      );
    }

    const inserted = await userRestRequest('/rest/v1/assignments', accessToken, {
      method: 'POST',
      prefer: 'return=representation',
      body: {
        roster_slot_id: testSlot.id,
        doctor_id: doctor.id,
        state: 'provisional',
        created_by: userId,
      },
    });
    const assignmentId = inserted?.[0]?.id;
    if (!assignmentId) {
      throw new Error('RLS assignment insert returned no created row.');
    }

    try {
      const removed = await userRestRequest(
        `/rest/v1/assignments?id=eq.${encodeURIComponent(assignmentId)}`,
        accessToken,
        { method: 'DELETE', prefer: 'return=representation' },
      );
      if (removed?.length !== 1) {
        throw new Error('RLS assignment delete did not remove the test row.');
      }
    } catch (error) {
      await serviceRestRequest(
        `/rest/v1/assignments?id=eq.${encodeURIComponent(assignmentId)}`,
        { method: 'DELETE' },
      );
      throw error;
    }

    console.log('Reviewer verification passed:');
    console.log('- confirmed email/password login without OTP or MFA');
    console.log('- own profile and linked active doctor are readable through RLS');
    console.log('- roster slots are readable through RLS');
    console.log('- a reviewer assignment was created and removed through RLS');
  } finally {
    await publicRequest('/auth/v1/logout', {
      method: 'POST',
      bearerToken: accessToken,
    }).catch(() => undefined);
  }
}

async function resetReviewerPassword() {
  const user = await requireReviewerUser();
  await adminRequest(`/auth/v1/admin/users/${encodeURIComponent(user.id)}`, {
    method: 'PUT',
    body: { password: reviewerPassword, email_confirm: true },
  });
  console.log('Reviewer password reset successfully; email remains confirmed.');
  console.log('Run verify with the new password before updating Play Console.');
}

async function deleteReviewer() {
  const user = await findUserByEmail(reviewerEmail);
  if (!user) {
    console.log('No reviewer Auth user exists; nothing was deleted.');
    return;
  }

  const doctors = await serviceRestRequest(
    `/rest/v1/doctors?select=id&auth_user_id=eq.${encodeURIComponent(user.id)}`,
  );
  for (const doctor of doctors ?? []) {
    await serviceRestRequest(
      `/rest/v1/assignments?doctor_id=eq.${encodeURIComponent(doctor.id)}`,
      { method: 'DELETE' },
    );
    await serviceRestRequest(
      `/rest/v1/absences?doctor_id=eq.${encodeURIComponent(doctor.id)}`,
      { method: 'DELETE' },
    );
    await serviceRestRequest(
      `/rest/v1/doctors?id=eq.${encodeURIComponent(doctor.id)}`,
      { method: 'DELETE' },
    );
  }
  await serviceRestRequest(
    `/rest/v1/profiles?id=eq.${encodeURIComponent(user.id)}`,
    { method: 'DELETE' },
  );
  await adminRequest(`/auth/v1/admin/users/${encodeURIComponent(user.id)}`, {
    method: 'DELETE',
  });
  console.log('Reviewer account, linked doctor, assignments, and absences deleted.');
}

async function rollbackCreatedReviewer(userId, doctorCreated) {
  if (doctorCreated) {
    await serviceRestRequest(
      `/rest/v1/doctors?auth_user_id=eq.${encodeURIComponent(userId)}`,
      { method: 'DELETE' },
    ).catch(() => undefined);
  }
  await serviceRestRequest(
    `/rest/v1/profiles?id=eq.${encodeURIComponent(userId)}`,
    { method: 'DELETE' },
  ).catch(() => undefined);
  await adminRequest(`/auth/v1/admin/users/${encodeURIComponent(userId)}`, {
    method: 'DELETE',
  }).catch(() => undefined);
}

async function requireReviewerUser() {
  const user = await findUserByEmail(reviewerEmail);
  if (!user) {
    throw new Error('No Supabase Auth user exists for the reviewer email.');
  }
  return user;
}

async function findUserByEmail(email) {
  for (let page = 1; page <= 100; page += 1) {
    const result = await adminRequest(
      `/auth/v1/admin/users?page=${page}&per_page=1000`,
    );
    const users = Array.isArray(result) ? result : result?.users ?? [];
    const match = users.find(
      (user) => String(user.email ?? '').toLowerCase() === email,
    );
    if (match) return match;
    if (users.length < 1000) return null;
  }
  throw new Error('User lookup exceeded 100 pages; no data was changed.');
}

function adminRequest(path, options = {}) {
  return request(path, {
    ...options,
    apiKey: serviceRoleKey,
    bearerToken: serviceRoleKey,
  });
}

function serviceRestRequest(path, options = {}) {
  return request(path, {
    ...options,
    apiKey: serviceRoleKey,
    bearerToken: serviceRoleKey,
  });
}

function userRestRequest(path, accessToken, options = {}) {
  return request(path, {
    ...options,
    apiKey: publishableKey || serviceRoleKey,
    bearerToken: accessToken,
  });
}

function publicRequest(path, options = {}) {
  return request(path, {
    ...options,
    apiKey: publishableKey || serviceRoleKey,
    bearerToken: options.bearerToken,
  });
}

async function request(
  path,
  { method = 'GET', body, prefer, apiKey, bearerToken } = {},
) {
  const headers = { apikey: apiKey };
  if (bearerToken) headers.Authorization = `Bearer ${bearerToken}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  if (prefer) headers.Prefer = prefer;

  const response = await fetch(`${supabaseUrl}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  let payload;
  try {
    payload = text ? JSON.parse(text) : null;
  } catch {
    payload = text;
  }

  if (!response.ok) {
    const detail =
      payload?.msg || payload?.message || payload?.error_description || payload?.error;
    throw new Error(
      `${method} ${path.split('?')[0]} failed (${response.status})` +
        (detail ? `: ${detail}` : ''),
    );
  }
  return payload;
}

function requiredEnvironment(name) {
  const value = process.env[name]?.trim();
  if (!value) fail(`Required environment variable ${name} is missing.`);
  return value;
}

function validateConfiguration() {
  const parsedUrl = new URL(supabaseUrl);
  if (!['https:', 'http:'].includes(parsedUrl.protocol)) {
    throw new Error('SUPABASE_URL must be an HTTP(S) URL.');
  }
  validateServiceRoleKey(serviceRoleKey);
  if (publishableKey) {
    validatePublishableKey(publishableKey);
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(reviewerEmail)) {
    throw new Error('GOOGLE_PLAY_REVIEWER_EMAIL must be a valid email address.');
  }
  if (action !== 'delete' && reviewerPassword.length < 16) {
    throw new Error('GOOGLE_PLAY_REVIEWER_PASSWORD must contain at least 16 characters.');
  }
}

function validatePublishableKey(value) {
  if (value.startsWith('sb_publishable_')) {
    if (value.length < 30) {
      throw new Error(
        'SUPABASE_PUBLISHABLE_KEY looks truncated or is still a placeholder.',
      );
    }
    return;
  }

  const parts = value.split('.');
  if (parts.length === 3) {
    try {
      const normalized = parts[1].replace(/-/g, '+').replace(/_/g, '/');
      const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, '=');
      const payload = JSON.parse(Buffer.from(padded, 'base64').toString('utf8'));
      if (payload.role === 'anon') return;
    } catch {
      // Report the single actionable error below.
    }
  }

  throw new Error(
    'SUPABASE_PUBLISHABLE_KEY is invalid. Copy the Publishable key from the ' +
      'same Supabase project as SUPABASE_URL, or remove this variable so the ' +
      'verification script can use its server-side fallback.',
  );
}

function validateServiceRoleKey(value) {
  if (value.startsWith('sb_publishable_')) {
    throw new Error(
      'SUPABASE_SERVICE_ROLE_KEY contains a publishable key. Replace it with ' +
        'the Legacy API Keys > service_role value from Supabase Dashboard.',
    );
  }
  if (value.startsWith('sb_secret_')) {
    throw new Error(
      'This script expects the Legacy API Keys > service_role JWT, not an ' +
        'sb_secret key.',
    );
  }

  const parts = value.split('.');
  if (parts.length !== 3) {
    throw new Error(
      'SUPABASE_SERVICE_ROLE_KEY is not a service_role JWT. Copy the value ' +
        'from Supabase Dashboard > Settings > API Keys > Legacy API Keys.',
    );
  }

  try {
    const normalized = parts[1].replace(/-/g, '+').replace(/_/g, '/');
    const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, '=');
    const payload = JSON.parse(Buffer.from(padded, 'base64').toString('utf8'));
    if (payload.role !== 'service_role') {
      throw new Error(
        `the JWT role is ${String(payload.role ?? 'missing')}, not service_role`,
      );
    }
  } catch (error) {
    throw new Error(
      `SUPABASE_SERVICE_ROLE_KEY is invalid: ${safeMessage(error)}. ` +
        'Use Legacy API Keys > service_role, never anon or publishable.',
    );
  }
}

function safeMessage(error) {
  return error instanceof Error ? error.message : String(error);
}

function fail(message) {
  console.error(`Error: ${message}`);
  process.exit(1);
}

function reportFailure(message) {
  console.error(`Error: ${message}`);
  process.exitCode = 1;
}
