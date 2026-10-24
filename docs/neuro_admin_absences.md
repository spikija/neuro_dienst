# Administrator removal of absences and day markers

EF days are stored in `public.absences` with type `ef_day`, separately from duty
assignments. The admin reader already loads these records. Previously the month
calendar showed only duties, and the EF entry could be found only below the daily
role list. There was no desktop action to remove it. Markers were also omitted
from daily details when the date had no generated `roster_days` row.

The calendar displays an icon for each recorded absence/day-marker type:
umbrella for Urlaub, bandages for sick leave, people for conference, plane for
external rotation, moon for 24-hour duty, bed for post-duty, clock/sun for ZAM,
medical bag for other outpatient clinic, and calendar symbols for other absence
and availability. EF retains its **EF** label. Hover a marker to see the localized
type and physician names. Overlapping periods for the same physician/type count
as one marker; multiple simultaneous types remain separately visible.

With a physician selected, calendar markers follow that physician; otherwise
they summarize the whole loaded directory. Dense dates show an explicit **+N**
marker whose tooltip lists the remaining types and names. Day-level tooltips
also retain the full list, including dates without generated roster days. The daily
roster lists markers before the roles, including dates without generated duties.
Every absence/day-marker type has a removal button. The confirmation identifies
its type, physician and exact date. Supported types include Urlaub, sick leave,
conference, external rotation, EF, ZAM late shift/daytime, other outpatient clinic,
other absence, availability, 24-hour duty and post-duty. Removal affects only the
chosen type and date; an overlapping EF day is retained when removing Urlaub.
Overlapping records of the same type are shown as one logical daily entry.

24-hour duty and next-day post-duty markers are independently removable. The
confirmation for a 24-hour marker explicitly explains this; it does not silently
remove a marker on another date. Duty-role assignments use their existing
assignment-removal flow.

## Deployment

Apply pending migrations, including
`supabase/migrations/202610240002_admin_remove_absence_day.sql`, to the same
Supabase project as the app, then rebuild/restart `neuro_admin`. The generic
removal RPC requires the existing versioning and admin-workspace migrations.
It requires an administrator with verified MFA and permits removal of entries
created by any physician. No ownership restriction is added for administrators.
Installing the migration does not change existing absence records.

The earlier `202610240001_admin_remove_ef_day.sql` and its EF-only RPC remain
unchanged, preserving older clients and their pending retry receipts. The updated
client uses `admin_remove_absence_day` for all types, including EF. Without the
new migration, it explains that the migration is required.

Removal validates the roster version under the existing workspace locks, removes
only records of the selected type for the selected physician/date, and splits covering periods
into their remaining dates. Notes, original creator and creation time are kept.
Other absence types, other physicians and all duty assignments are retained.
Every successful request has an audit entry and an actor-scoped retry receipt.
If the response is lost, **Retry same request** uses the same request ID.

No live database was queried or modified during this change. To verify the
reported entry for Johanna Mayrhofer on 18 November 2026, an authorized database
administrator can run this read-only query in the target project's SQL editor:

```sql
select d.id as physician_id, d.first_name, d.last_name,
       a.id as absence_id, a.type, a.starts_on, a.ends_on
from public.doctors d
left join public.absences a on a.doctor_id = d.id
  and a.starts_on <= date '2026-11-18'
  and a.ends_on >= date '2026-11-18'
where lower(d.first_name) = 'johanna'
  and lower(d.last_name) = 'mayrhofer'
order by a.starts_on, a.id;
```

## Verification

The UI regression fixture reproduces Johanna's reported November date without
using live data. It verifies visibility with and without a generated roster day,
confirmation, exact date/physician selection, reload after removal, adjacent EF
dates, disabled writes for unversioned data, cancellation and uncertain retries.

The isolated SQL tests execute the migrations in PostgreSQL/WASM, checking admin
and MFA enforcement, period splitting, unchanged unrelated entries and metadata,
duplicate EF records, stale versions, date scope, audit/retry behavior, and full
rollback when inserting a retained period fails. They do not verify independent
PostgreSQL connection races or deployment to the live project.

```powershell
node supabase/tests/admin_absences.mjs neuro_admin/build/ef-day-test-tools
node supabase/tests/admin_ef_days.mjs neuro_admin/build/ef-day-test-tools
```

The supplied tools directory must contain `@electric-sql/pglite`. Flutter and
service regressions are `neuro_admin/test/absence_removal_test.dart`,
`neuro_admin/test/ef_day_test.dart`,
`neuro_admin/test/calendar_day_markers_test.dart` and
`neuro_admin_services/test/absence_day_removal_test.dart`. Calendar regressions
cover physician filtering, localized overflow in both themes, missing generated
days, duplicate periods and updates after removal. The generic regression
suite verifies all database enum types, including legacy spellings for external
rotation and 24-hour duty, receipt binding to the exact type, coexistence with
other absences, invalid types and paired-marker date boundaries.
