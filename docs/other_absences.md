# Additional full-day absences

The calendar action menu offers **Andere Abwesenheit…** and
**Andere Abwesenheit entfernen**. Reasons are Spätdienst im ZAM, ZAM tagsüber,
Andere Ambulanz, Kongress, and Andere (no free text required).

Each reason blocks only the selected working days, including morning duties.
Weekends, public holidays, selection gaps, and the following day are unaffected.
Existing assignments on affected days are removed. Choosing a different reason
replaces additional absence reasons on those days. Removal preserves Urlaub,
24-h-Dienst, post-duty days, and EF-Tag and does not restore deleted assignments.

Apply `supabase/migrations/202610040003_other_absence_types.sql` before releasing
the updated client. Kongress uses the existing `conference` database value;
the other four reasons have new enum values. Existing absence RLS policies apply.
Older clients do not recognize the new values and may display them as vacation.
