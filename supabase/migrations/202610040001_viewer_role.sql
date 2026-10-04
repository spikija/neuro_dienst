-- Separate migration so the enum value is committed before it is used.
alter type public.app_role add value if not exists 'viewer';
