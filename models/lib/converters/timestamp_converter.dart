import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:intl/intl.dart';

class TimestampConverter implements JsonConverter<DateTime, int> {
  const TimestampConverter();
  @override
  DateTime fromJson(int json) =>
      DateTime.fromMillisecondsSinceEpoch(json * 1000);
  @override
  int toJson(DateTime dateTime) => dateTime.millisecondsSinceEpoch ~/ 1000;
}

class YYYYMMDDConverter implements JsonConverter<DateTime, String> {
  const YYYYMMDDConverter();

  @override
  DateTime fromJson(String value) => DateFormat('yyyy-MM-dd').parse(value);

  @override
  String toJson(DateTime value) => DateFormat('yyyy-MM-dd').format(value);
}

class YYYYMMDDTHISConverter implements JsonConverter<DateTime, String> {
  const YYYYMMDDTHISConverter();

  /// Named once and read by both directions.
  ///
  /// They were two literals, and they had drifted: `toJson` wrote the time and
  /// `fromJson` parsed `'yyyy-MM-dd'`. `DateFormat.parse` is non-strict, so the
  /// trailing time was dropped rather than rejected — a value this converter
  /// wrote did not survive this converter reading it, silently.
  static const _pattern = 'yyyy-MM-ddTHH:mm:ss';

  @override
  DateTime fromJson(String value) => DateFormat(_pattern).parse(value);

  @override
  String toJson(DateTime value) => DateFormat(_pattern).format(value);
}
