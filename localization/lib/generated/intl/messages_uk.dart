// DO NOT EDIT. This is code generated via package:intl/generate_localized.dart
// This is a library that provides messages for a uk locale. All the
// messages from the main program should be duplicated here with the same
// function name.

// Ignore issues from commonly used lints in this file.
// ignore_for_file:unnecessary_brace_in_string_interps, unnecessary_new
// ignore_for_file:prefer_single_quotes,comment_references, directives_ordering
// ignore_for_file:annotate_overrides,prefer_generic_function_type_aliases
// ignore_for_file:unused_import, file_names, avoid_escaping_inner_quotes
// ignore_for_file:unnecessary_string_interpolations, unnecessary_string_escapes

import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'uk';

  static String m0(value) => "Мінімальна довжина — ${value} символів";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
    "_locale": MessageLookupByLibrary.simpleMessage("uk"),
    "appTitle": MessageLookupByLibrary.simpleMessage("Flutter Application 1"),
    "backToLogIn": MessageLookupByLibrary.simpleMessage("Назад до входу"),
    "cancel": MessageLookupByLibrary.simpleMessage("Скасувати"),
    "confirmPassword": MessageLookupByLibrary.simpleMessage(
      "Підтвердіть пароль",
    ),
    "couldNotConnectToInternet": MessageLookupByLibrary.simpleMessage(
      "Не вдалося підключитися до інтернету.",
    ),
    "darkTheme": MessageLookupByLibrary.simpleMessage("Темна тема"),
    "email": MessageLookupByLibrary.simpleMessage("Електронна пошта"),
    "forgotPassword": MessageLookupByLibrary.simpleMessage("Забули пароль?"),
    "invalidEmail": MessageLookupByLibrary.simpleMessage(
      "Некоректна електронна пошта",
    ),
    "lightTheme": MessageLookupByLibrary.simpleMessage("Світла тема"),
    "logIn": MessageLookupByLibrary.simpleMessage("Увійти"),
    "logInSubtitle": MessageLookupByLibrary.simpleMessage(
      "Увійдіть, щоб продовжити.",
    ),
    "minimumLengthSymbols": m0,
    "mustContainAtLeastOneLowercase": MessageLookupByLibrary.simpleMessage(
      "Має містити хоча б одну малу літеру",
    ),
    "mustContainAtLeastOneUppercase": MessageLookupByLibrary.simpleMessage(
      "Має містити хоча б одну велику літеру",
    ),
    "ok": MessageLookupByLibrary.simpleMessage("OK"),
    "password": MessageLookupByLibrary.simpleMessage("Пароль"),
    "passwordsDoNotMatch": MessageLookupByLibrary.simpleMessage(
      "Паролі не збігаються",
    ),
    "pleaseCheckYourNetworkSettings": MessageLookupByLibrary.simpleMessage(
      "Перевірте налаштування мережі.",
    ),
    "register": MessageLookupByLibrary.simpleMessage("Зареєструватися"),
    "requiredField": MessageLookupByLibrary.simpleMessage("Обов’язкове поле"),
    "resetPassword": MessageLookupByLibrary.simpleMessage("Скинути пароль"),
  };
}
