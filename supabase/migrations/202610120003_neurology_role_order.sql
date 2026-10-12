-- One-time configuration update; clients continue to use editable role ordering.
-- ICB and an explicitly named ICB AMB code remain distinct database identities.
with requested(code, position) as (
  values ('SUL', 1), ('SU1', 2), ('SU2', 3), ('AMB', 4),
         ('SON', 5), ('NVB', 6), ('OFO', 7), ('ICB', 8), ('ICB AMB', 9)
), ordered as (
  select r.id,
    (row_number() over (
      order by coalesce(requested.position, 100), r.display_order, r.code, r.id
    ) * 10)::integer as position
  from public.roles r left join requested on requested.code = r.code
)
update public.roles r set display_order = ordered.position
from ordered where r.id = ordered.id and r.display_order <> ordered.position;
