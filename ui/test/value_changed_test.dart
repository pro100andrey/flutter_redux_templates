import 'package:flutter_test/flutter_test.dart';
import 'package:ui/models/value_changed.dart';

void _ignore(Object? _) {}

String? _fails(Object? _) => 'nope';

/// What [FieldVm.props] leaves out is load-bearing and invisible.
///
/// A connector's `_Vm` declares `equals: [email, …]`, and `Vm.operator ==`
/// compares those elements — so if `FieldVm` counted `onChanged` or `validator`
/// in its own equality, every VM would differ from the last (the closures are
/// rebuilt on each `fromStore`) and every dispatch would rebuild every
/// connected widget. The exclusion is a performance contract with no compiler
/// support and no analyzer rule behind it. This file is the support.
void main() {
  group('FieldVm equality counts what is displayed', () {
    test('same value, error and enabled — equal', () {
      expect(
        const FieldVm<String?>(value: 'a', onChanged: _ignore),
        const FieldVm<String?>(value: 'a', onChanged: _ignore),
      );
    });

    test('a different value — not equal', () {
      expect(
        const FieldVm<String?>(value: 'a', onChanged: _ignore),
        isNot(const FieldVm<String?>(value: 'b', onChanged: _ignore)),
      );
    });

    test('a different error — not equal', () {
      expect(
        const FieldVm<String?>(value: 'a', onChanged: _ignore, error: 'x'),
        isNot(const FieldVm<String?>(value: 'a', onChanged: _ignore)),
      );
    });

    test('a different enabled — not equal', () {
      expect(
        const FieldVm<String?>(
          value: 'a',
          onChanged: _ignore,
          enabled: false,
        ),
        isNot(const FieldVm<String?>(value: 'a', onChanged: _ignore)),
      );
    });
  });

  group('FieldVm equality ignores behaviour', () {
    test('a different onChanged — still equal', () {
      // The one that matters. `fromStore()` builds a fresh closure every call,
      // so counting it here would make every rebuild unavoidable.
      expect(
        FieldVm<String?>(value: 'a', onChanged: (_) {}),
        FieldVm<String?>(value: 'a', onChanged: (_) {}),
      );
    });

    test('a different validator — still equal', () {
      expect(
        const FieldVm<String?>(
          value: 'a',
          onChanged: _ignore,
          validator: _fails,
        ),
        const FieldVm<String?>(value: 'a', onChanged: _ignore),
      );
    });
  });

  group('ChoiceVm', () {
    const items = [
      ChoiceItemVm(value: 'en', label: 'English'),
      ChoiceItemVm(value: 'uk', label: 'Ukrainian'),
    ];

    test('counts its items, because they are displayed', () {
      expect(
        const ChoiceVm<String>(
          value: 'en',
          items: items,
          onChanged: _ignore,
        ),
        isNot(
          const ChoiceVm<String>(
            value: 'en',
            items: [ChoiceItemVm(value: 'en', label: 'English')],
            onChanged: _ignore,
          ),
        ),
      );
    });

    test('ignores behaviour, same as FieldVm', () {
      expect(
        ChoiceVm<String>(value: 'en', items: items, onChanged: (_) {}),
        ChoiceVm<String>(value: 'en', items: items, onChanged: (_) {}),
      );
    });
  });

  group('ChoiceItemVm', () {
    test('is a value over both fields', () {
      expect(
        const ChoiceItemVm(value: 'en', label: 'English'),
        const ChoiceItemVm(value: 'en', label: 'English'),
      );
      expect(
        const ChoiceItemVm(value: 'en', label: 'English'),
        isNot(const ChoiceItemVm(value: 'en', label: 'Англійська')),
      );
    });
  });
}
