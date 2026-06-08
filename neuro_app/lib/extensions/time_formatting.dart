import 'package:neuro_core/neuro_core.dart';

extension LocalTimeFormatting on LocalTime {
  String get hhmm {
    return '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
  }
}

extension TimeRangeFormatting on TimeRange {
  String get display {
    return '${start.hhmm}–${end.hhmm}';
  }
}