-- One-time compatibility repair for installed mobile clients that start in
-- June 2026 and navigate one month at a time. Run as the database administrator
-- in the Supabase SQL Editor. Creates calendar records, never duty slots or
-- assignments; existing roster records and absences are preserved.
-- Keep these calendar months until a future mobile release removes the fixed
-- June startup dependency. Deleting them again would block installed clients.
BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.rosters WHERE year = 2026 AND month = 11
  ) THEN
    RAISE EXCEPTION 'Repair cancelled: November 2026 roster was not found.';
  END IF;
END;
$$;

-- Preserve the security configuration required by the application schema.
-- These statements are safe when RLS is already enabled and do not replace
-- existing read/write policies or grant any additional client permissions.
ALTER TABLE public.rosters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.roster_days ENABLE ROW LEVEL SECURITY;

INSERT INTO public.rosters (year, month, phase)
SELECT 2026, m, 'draft'::public.roster_phase
FROM generate_series(6, 10) AS months(m)
ON CONFLICT (year, month) DO NOTHING;

-- Days are necessary: the installed calendar reads its first day to lay out
-- the month. An empty roster header by itself would cause another error.
WITH calendar AS (
  SELECT r.id AS roster_id, make_date(r.year, r.month, d) AS day_date
  FROM public.rosters r
  CROSS JOIN LATERAL generate_series(
    1,
    extract(day FROM (
      make_date(r.year, r.month, 1) + interval '1 month - 1 day'
    ))::integer
  ) AS days(d)
  WHERE r.year = 2026 AND r.month BETWEEN 6 AND 10
), holidays(day_date, name) AS (
  VALUES
    (DATE '2026-06-04', 'Fronleichnam'),
    (DATE '2026-08-15', 'Mariä Himmelfahrt'),
    (DATE '2026-10-26', 'Nationalfeiertag')
)
INSERT INTO public.roster_days (
  roster_id, date, is_weekend, is_public_holiday, public_holiday_name
)
SELECT c.roster_id, c.day_date,
       extract(isodow FROM c.day_date) IN (6, 7),
       h.day_date IS NOT NULL, h.name
FROM calendar c
LEFT JOIN holidays h ON h.day_date = c.day_date
ON CONFLICT (roster_id, date) DO NOTHING;

COMMIT;

-- Expected for newly restored June-October: 30/31 calendar days, zero slots
-- and zero assignments. November's existing roster remains available.
SELECT r.year, r.month,
       count(DISTINCT d.id) AS calendar_days,
       count(DISTINCT s.id) AS duty_slots,
       count(DISTINCT a.id) AS assignments
FROM public.rosters r
LEFT JOIN public.roster_days d ON d.roster_id = r.id
LEFT JOIN public.roster_slots s ON s.roster_day_id = d.id
LEFT JOIN public.assignments a ON a.roster_slot_id = s.id
WHERE r.year = 2026 AND r.month BETWEEN 6 AND 11
GROUP BY r.year, r.month
ORDER BY r.year, r.month;
