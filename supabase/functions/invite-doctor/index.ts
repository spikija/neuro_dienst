import { createClient } from 'npm:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
}

const allowedRanks = new Set([
  'resident',
  'specialist',
  'senior_specialist',
  'consultant',
  'head',
])

const allowedCapabilities = new Set([
  'can_lead',
  'can_work_outpatient_clinic',
  'can_do_neurosonography',
  'can_do_night_duty',
  'can_supervise',
])

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (request.method !== 'POST') {
    return jsonResponse(405, { error: 'Method not allowed.' })
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const authorization = request.headers.get('Authorization')

  if (!supabaseUrl || !anonKey || !serviceRoleKey || !authorization) {
    return jsonResponse(401, { error: 'Authentication is required.' })
  }

  const accessToken = authorization.replace(/^Bearer\s+/i, '')
  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const { data: userData, error: userError } =
    await callerClient.auth.getUser(accessToken)

  if (userError || !userData.user) {
    return jsonResponse(401, { error: 'The session is invalid or expired.' })
  }

  const jwtPayload = decodeJwtPayload(accessToken)
  if (jwtPayload?.aal !== 'aal2') {
    return jsonResponse(403, {
      error: 'Two-factor verification is required before inviting a doctor.',
    })
  }

  const { data: profile, error: profileError } = await callerClient
    .from('profiles')
    .select('role')
    .eq('id', userData.user.id)
    .maybeSingle()

  if (profileError || profile?.role !== 'admin') {
    return jsonResponse(403, { error: 'Administrator access is required.' })
  }

  let body: Record<string, unknown>
  try {
    body = await request.json()
  } catch (_) {
    return jsonResponse(400, { error: 'A JSON request body is required.' })
  }

  const email = normalizedString(body.email).toLowerCase()
  const firstName = normalizedString(body.firstName)
  const lastName = normalizedString(body.lastName)
  const rank = normalizedString(body.rank)
  const preferredLanguage = normalizedString(body.preferredLanguage) || 'en'
  const capabilities = Array.isArray(body.capabilities)
    ? body.capabilities.filter(
        (value): value is string =>
          typeof value === 'string' && allowedCapabilities.has(value),
      )
    : []

  if (!emailPattern.test(email)) {
    return jsonResponse(400, { error: 'Enter a valid email address.' })
  }
  if (!firstName || !lastName) {
    return jsonResponse(400, { error: 'First name and last name are required.' })
  }
  if (!allowedRanks.has(rank)) {
    return jsonResponse(400, { error: 'The selected rank is invalid.' })
  }
  if (!['en', 'de'].includes(preferredLanguage)) {
    return jsonResponse(400, { error: 'The selected language is invalid.' })
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const displayName = `${firstName} ${lastName}`
  const { data: createdUser, error: createUserError } =
    await adminClient.auth.admin.createUser({
      email,
      email_confirm: true,
      user_metadata: {
        display_name: displayName,
        invited_by: userData.user.id,
      },
    })

  if (createUserError || !createdUser.user) {
    const message = createUserError?.message.toLowerCase().includes('already')
      ? 'An account with this email already exists.'
      : createUserError?.message || 'Could not create the account.'
    return jsonResponse(409, { error: message })
  }

  const newUserId = createdUser.user.id
  let doctorId: string | null = null

  try {
    const { error: insertProfileError } = await adminClient
      .from('profiles')
      .insert({
        id: newUserId,
        role: 'doctor',
        display_name: displayName,
        preferred_language: preferredLanguage,
      })
    if (insertProfileError) throw insertProfileError

    const { data: highestPrintOrder, error: printOrderError } =
      await adminClient
        .from('doctors')
        .select('print_order')
        .order('print_order', { ascending: false })
        .limit(1)
        .maybeSingle()
    if (printOrderError) throw printOrderError

    const { data: doctor, error: insertDoctorError } = await adminClient
      .from('doctors')
      .insert({
        auth_user_id: newUserId,
        first_name: firstName,
        last_name: lastName,
        rank,
        capabilities,
        is_active: true,
        print_order: (highestPrintOrder?.print_order ?? 0) + 1,
      })
      .select('id')
      .single()
    if (insertDoctorError) throw insertDoctorError
    doctorId = doctor.id

    const mailClient = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    })
    const { error: mailError } = await mailClient.auth.resetPasswordForEmail(
      email,
      { redirectTo: 'io.neurodienst.app://auth/reset-password' },
    )
    if (mailError) throw mailError
  } catch (error) {
    if (doctorId) {
      await adminClient.from('doctors').delete().eq('id', doctorId)
    }
    await adminClient.auth.admin.deleteUser(newUserId)

    return jsonResponse(500, {
      error: error instanceof Error
        ? error.message
        : 'Could not finish creating the doctor account.',
    })
  }

  return jsonResponse(201, {
    message: 'Doctor created and password-setup email sent.',
    doctorId,
  })
})

const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

function normalizedString(value: unknown): string {
  return typeof value === 'string' ? value.trim() : ''
}

function decodeJwtPayload(token: string): Record<string, unknown> | null {
  try {
    const value = token.split('.')[1]
    const normalized = value.replace(/-/g, '+').replace(/_/g, '/')
    const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, '=')
    return JSON.parse(atob(padded))
  } catch (_) {
    return null
  }
}

function jsonResponse(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
