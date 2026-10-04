-- Additional full-working-day absences. None creates a post-duty day.
-- Congress uses the existing conference value.
alter type public.availability_type add value if not exists 'zam_late_shift';
alter type public.availability_type add value if not exists 'zam_daytime';
alter type public.availability_type add value if not exists 'other_outpatient_clinic';
alter type public.availability_type add value if not exists 'other_absence';
