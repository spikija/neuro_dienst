alter table public.roles
add column if not exists print_in_report boolean not null default true;
