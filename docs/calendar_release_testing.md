# Calendar usability and app integration

## Interaction checks on a phone

- Tap a date: it is selected and the bottom-right action menu opens automatically.
  The full roles page stays closed. Dismiss the menu and tap another date to add
  a non-adjacent date; tapping a selected date deselects it.
- Hold a date, then release without dragging: the full day/roles page opens,
  including on weekends and holidays. A hover tooltip remains available to mouse
  users without competing with the touch gesture.
- Hold for about half a second, drag to another date, then release: every date in
  the range is highlighted, and the action menu opens on release. Test forward
  and backward ranges, across weeks and the narrow Saturday/Sunday cells.
- Swipe left/right across the calendar without holding: next/previous month.
  Test short and slow swipes, the December/January boundary, and rapid repeated
  swipes during loading. Swiping must not select a date or open the roles page.
- At an unavailable month, the current roster stays visible and the status strip
  names the month with no generated roster. Test both directions with real data.
- In both role and physician reports, drag the assignment columns left/right:
  date and weekday stay fixed at the left. Scroll vertically: dates and assignment
  rows move together and remain aligned, including shorter weekend/holiday rows.

Automated gesture and report checks live in `neuro_app/test/month_interactions_test.dart`
and `neuro_app/test/month_report_scroll_test.dart`.

## Choosing calendar apps

The export screen already has a **Phone calendar** selector backed by
`DeviceCalendarExportService.writableCalendars()`. It lists writable calendars
exposed by the device, labels them with the calendar/account name, and passes the
chosen calendar ID to the export operation. It also offers ICS sharing/saving.
The explanatory and completion messages now support any calendar app.

Recommended approach for this release: keep the device calendar selector and ICS
fallback. A calendar app and a calendar account are different: installing an app
does not guarantee that its calendars are available through the phone's calendar
store. Android exposes calendar/account records through its
[Calendar Provider](https://developer.android.com/identity/providers/calendar-provider).
Users should connect/enable the desired calendar account on their phone and choose
that calendar in NeuroDienst. Apps which do not expose their calendars need another
route, such as an ICS import or a provider-specific integration.

| Option | Best use and tradeoff |
| --- | --- |
| Existing device calendar selector | The simplest route for calendars already accessible to the phone. No separate provider login in NeuroDienst. Test each supported account/device combination. |
| Existing ICS sharing/saving | A portable snapshot for other calendar apps. The operating system controls available share targets; not every app accepts calendar files via sharing. Google documents ICS import on a computer. Repeated imports may duplicate events and changes do not automatically sync. |
| Remember the chosen calendar | A small future usability improvement: persist the calendar ID per signed-in user/device, revalidate availability before each export, and ask for a replacement if removed. |
| Private subscription feed | A future option for automatic roster updates in clients that support calendar subscriptions. Requires a server endpoint and revocable, user-specific access; client refresh timing varies. |
| Google Calendar / Microsoft Graph integrations | A future option for accounts unavailable through device calendars. Requires provider OAuth, token management and explicit event update/delete handling. Higher implementation and maintenance cost. |

Google's [ICS import instructions](https://support.google.com/calendar/answer/37118?hl=en)
also state that imported events do not remain synchronized with the original calendar.

For release validation, use two writable calendars, export to each in turn and
confirm events land only in the selected target. Re-export the same month after a
roster edit and check for duplicates/stale entries. Check overnight duties and
timezone/DST boundaries. Deny calendar permission and confirm ICS export remains
available; separately test the saved file in the calendar apps used by your team.
