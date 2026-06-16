alter table if exists public.doctors
add column if not exists print_order integer not null default 0;

with ordered_doctors as (
  select
    id,
    row_number() over (
      order by last_name nulls last, first_name nulls last, id
    ) as row_number
  from public.doctors
)
update public.doctors
set print_order = ordered_doctors.row_number
from ordered_doctors
where doctors.id = ordered_doctors.id
  and doctors.print_order = 0;

create index if not exists doctors_print_order_idx
on public.doctors (print_order, last_name, first_name);

