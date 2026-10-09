import 'package:flutter/material.dart';

@immutable
class CalendarColors extends ThemeExtension<CalendarColors> {
  final Color assignable;
  final Color tint;
  final Color selected;
  final Color warning;
  const CalendarColors(this.assignable, this.tint, this.selected, this.warning);
  factory CalendarColors.forScheme(ColorScheme scheme) => CalendarColors(
    scheme.primary,
    scheme.primaryContainer.withValues(alpha: .28),
    scheme.primaryContainer,
    ColorScheme.fromSeed(
      seedColor: Colors.amber,
      brightness: scheme.brightness,
    ).primary,
  );
  @override
  CalendarColors copyWith({
    Color? assignable,
    Color? tint,
    Color? selected,
    Color? warning,
  }) => CalendarColors(
    assignable ?? this.assignable,
    tint ?? this.tint,
    selected ?? this.selected,
    warning ?? this.warning,
  );
  @override
  CalendarColors lerp(covariant CalendarColors? other, double t) =>
      other == null
      ? this
      : CalendarColors(
          Color.lerp(assignable, other.assignable, t)!,
          Color.lerp(tint, other.tint, t)!,
          Color.lerp(selected, other.selected, t)!,
          Color.lerp(warning, other.warning, t)!,
        );
}

ThemeData adminTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: Colors.blue,
    brightness: brightness,
  );
  return ThemeData(
    colorScheme: scheme,
    extensions: [CalendarColors.forScheme(scheme)],
  );
}
