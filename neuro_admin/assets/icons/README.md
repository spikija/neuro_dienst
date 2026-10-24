The absence SVGs contain the outlines of Google Material Icons, converted from
Flutter's bundled `MaterialIcons-Regular.otf` to standalone 24 x 24 SVG paths.
Their shapes match the `absenceIcon` mapping in `lib/absence_icons.dart`.

The PDF renderer needs vector paths because it cannot embed the CFF icon font.
These assets require no downloads or external resources during export.

Source: https://github.com/google/material-design-icons
License: Apache 2.0; see LICENSE.txt.
