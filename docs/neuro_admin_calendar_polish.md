# Monthly calendar visual polish

Previous/next buttons are 48 px desktop targets with localized tooltips. The
localized month label retains the existing direct roster/revision dropdown.
Explicit month controls clear bulk selection as before; the focus day is retained
and clamped to the target month's length. Keyboard day/week movement retains its
existing independent-focus behavior. Existing request/version checks and mounted
loading/error transitions remain intact; missing months do not generate rosters.

The calendar uses a single clipped surface with a modest 4 px outer radius,
0.5 px cell dividers and no cell gaps. Focus, selection and assignability borders
sit above structural grid lines. Existing role indicators, holiday/weekend tints,
blocked states and dynamic row heights remain present. The today underline uses
Europe/Vienna's current date and is independent of focused/selected dates.

Day numbers use 17 px semibold type (bold when selected) and scale independently
of status text when needed in narrow cells. Weekday headers use 13 px semibold
with 8 px vertical padding; calendar inset is reduced from 12 px to 8 px.

Tests cover adjacent and direct navigation, focus clamping, mounted loading and
failure, continuous cell geometry, today, mouse/keyboard selection, and usability
at 1280x720, 1440x900 and 1920x1080.

Verified: flutter analyze clean; 111 desktop tests and 55 shared-service tests
pass; Windows release build succeeds. PDF/PyMuPDF checks pass for the existing
reports and selected-column portrait/landscape PDFs. No live data changes.
