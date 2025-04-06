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

  @override
  DateTime fromJson(String value) => DateFormat('yyyy-MM-dd').parse(value);

  @override
  String toJson(DateTime value) => DateFormat(
    'yyyy-MM-dd'
    'T'
    'HH:mm:ss',
  ).format(value);
}
