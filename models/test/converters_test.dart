import 'package:models/converters/bool_converter.dart';
import 'package:models/converters/timestamp_converter.dart';
import 'package:test/test.dart';

/// The converters are the only pure-Dart values in the template, so this is the
/// cheapest test there is: no binding, no store, no fixture. It is first for
/// that reason — it proves the runner works before anything harder depends on
/// it being able to.
void main() {
  group('BoolConverter', () {
    test('reads a non-zero int as true and zero as false', () {
      const c = BoolConverter();
      expect(c.fromJson(1), isTrue);
      expect(c.fromJson(42), isTrue);
      expect(c.fromJson(0), isFalse);
    });

    test('writes a bool back as the int it came from', () {
      const c = BoolConverter();
      expect(c.toJson(true), 1);
      expect(c.toJson(false), 0);
    });

    test('refuses anything that is not an int — including a real bool', () {
      // Worth pinning rather than assuming: the name says "bool converter", so
      // `fromJson(true)` reads like it should work. It throws. A server that
      // starts sending JSON `true` where it used to send `1` breaks here, and
      // the message names the value.
      const c = BoolConverter();
      expect(() => c.fromJson(true), throwsArgumentError);
      expect(() => c.fromJson('1'), throwsArgumentError);
    });
  });

  group('OptionalBoolConverter', () {
    test('passes null through in both directions', () {
      const c = OptionalBoolConverter();
      expect(c.fromJson(null), isNull);
      expect(c.toJson(null), isNull);
    });

    test('delegates a non-null value to BoolConverter', () {
      const c = OptionalBoolConverter();
      expect(c.fromJson(1), isTrue);
      expect(c.toJson(false), 0);
    });
  });

  group('TimestampConverter', () {
    test('the wire unit is seconds, not milliseconds', () {
      const c = TimestampConverter();
      expect(
        c.fromJson(1),
        DateTime.fromMillisecondsSinceEpoch(1000),
        reason: 'a value multiplied by 1000 on read is seconds on the wire',
      );
    });

    test('round-trips a whole second', () {
      const c = TimestampConverter();
      final at = DateTime(2026, 8, 5, 14, 30, 15);
      expect(c.fromJson(c.toJson(at)), at);
    });

    test('drops sub-second precision, which is what seconds means', () {
      const c = TimestampConverter();
      final at = DateTime(2026, 8, 5, 14, 30, 15, 750);
      expect(c.fromJson(c.toJson(at)), DateTime(2026, 8, 5, 14, 30, 15));
    });
  });

  group('YYYYMMDDConverter', () {
    test('round-trips a date', () {
      const c = YYYYMMDDConverter();
      final day = DateTime(2026, 8, 5);
      expect(c.fromJson(c.toJson(day)), day);
    });

    test('drops the time, which is what a date-only format means', () {
      const c = YYYYMMDDConverter();
      expect(c.toJson(DateTime(2026, 8, 5, 14, 30)), '2026-08-05');
    });
  });

  group('YYYYMMDDTHISConverter', () {
    test('writes the time it was given', () {
      const c = YYYYMMDDTHISConverter();
      expect(c.toJson(DateTime(2026, 8, 5, 14, 30, 15)), '2026-08-05T14:30:15');
    });

    test('round-trips the value it wrote', () {
      // The whole point of the type: it exists to carry a time, and its name
      // says so. `fromJson` parses with 'yyyy-MM-dd' while `toJson` formats
      // with 'yyyy-MM-ddTHH:mm:ss', and `DateFormat.parse` is non-strict — so
      // the trailing time is silently dropped rather than rejected. A value
      // written by this converter does not survive being read by it.
      const c = YYYYMMDDTHISConverter();
      final at = DateTime(2026, 8, 5, 14, 30, 15);
      expect(c.fromJson(c.toJson(at)), at);
    });
  });
}
