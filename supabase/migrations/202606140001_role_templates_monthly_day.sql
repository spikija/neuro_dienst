alter type public.weekday_rule add value if not exists 'monthly_day';

alter table public.role_templates
add column if not exists monthly_day integer;

alter table public.role_templates
drop constraint if exists role_templates_monthly_day_check;

alter table public.role_templates
add constraint role_templates_monthly_day_check
check (monthly_day is null or monthly_day between 1 and 31);
