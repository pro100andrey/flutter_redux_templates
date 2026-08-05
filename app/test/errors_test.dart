import 'package:app/errors.dart';
import 'package:async_redux/async_redux.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';

void main() {
  // The validators and this translator both read `S.current`, which is null
  // until a locale is loaded. One await, once, for the whole file.
  setUpAll(() => S.load(const Locale('en')));

  test('a deliberate UserException is left alone', () {
    // Returning null is how the translator says "nothing to add", and
    // `_MyErrorObserver` then passes the exception through untouched — keeping
    // any `onOk` / `onCancel` callbacks and `code` it carries. Re-wrapping it
    // would drop them.
    expect(translateError(const UserException('Not implemented yet.')), isNull);
  });

  test('anything else becomes a sentence, not a Dart toString()', () {
    final message = translateError(StateError('boom'));

    expect(message, isNotNull);
    expect(message!.title, isNotEmpty);
    expect(message.message, isNotEmpty);
    expect(
      '${message.title}${message.message}',
      isNot(contains('StateError')),
      reason: 'the detail belongs in the log, not in a dialog',
    );
  });

  test('a null error still produces something showable', () {
    final message = translateError(null);

    expect(message?.title, isNotEmpty);
    expect(message?.message, isNotEmpty);
  });

  test('title and message are different strings', () {
    // The behaviour this whole path was wired to end: the untranslated
    // fallback in `store.dart` passes the same text as both, so the dialog
    // showed one sentence twice.
    final message = translateError(Exception('x'));

    expect(message!.title, isNot(message.message));
  });
}
