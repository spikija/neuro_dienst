alter table if exists public.profiles
add column if not exists preferred_language text not null default 'en'
check (preferred_language in ('en', 'de'));

