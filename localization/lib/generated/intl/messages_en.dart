// DO NOT EDIT. This is code generated via package:intl/generate_localized.dart
// This is a library that provides messages for a en locale. All the
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
  String get localeName => 'en';

  static String m0(value) => "Minimum length ${value} symbols";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
    "_locale": MessageLookupByLibrary.simpleMessage("en"),
    "appTitle": MessageLookupByLibrary.simpleMessage("Flutter Application 1"),
    "backToLogIn": MessageLookupByLibrary.simpleMessage("Back to log in"),
    "cancel": MessageLookupByLibrary.simpleMessage("Cancel"),
    "checkYourConnection": MessageLookupByLibrary.simpleMessage(
      "Check your connection and try again.",
    ),
    "confirmPassword": MessageLookupByLibrary.simpleMessage("Confirm password"),
    "couldNotConnectToInternet": MessageLookupByLibrary.simpleMessage(
      "Couldn\'t connect to internet.",
    ),
    "darkTheme": MessageLookupByLibrary.simpleMessage("Dark theme"),
    "email": MessageLookupByLibrary.simpleMessage("Email"),
    "forgotPassword": MessageLookupByLibrary.simpleMessage("Forgot password?"),
    "invalidEmail": MessageLookupByLibrary.simpleMessage("Invalid email"),
    "lightTheme": MessageLookupByLibrary.simpleMessage("Light theme"),
    "logIn": MessageLookupByLibrary.simpleMessage("Log in"),
    "logInSubtitle": MessageLookupByLibrary.simpleMessage(
      "Sign in to continue.",
    ),
    "logOut": MessageLookupByLibrary.simpleMessage("Log out"),
    "minimumLengthSymbols": m0,
    "mustContainAtLeastOneLowercase": MessageLookupByLibrary.simpleMessage(
      "Must contain at least one lowercase",
    ),
    "mustContainAtLeastOneUppercase": MessageLookupByLibrary.simpleMessage(
      "Must contain at least one uppercase",
    ),
    "networkError": MessageLookupByLibrary.simpleMessage("Connection problem"),
    "ok": MessageLookupByLibrary.simpleMessage("OK"),
    "password": MessageLookupByLibrary.simpleMessage("Password"),
    "passwordsDoNotMatch": MessageLookupByLibrary.simpleMessage(
      "Passwords do not match",
    ),
    "pleaseCheckYourNetworkSettings": MessageLookupByLibrary.simpleMessage(
      "Please check your network settings.",
    ),
    "pleaseLogInAgain": MessageLookupByLibrary.simpleMessage(
      "Please log in again.",
    ),
    "register": MessageLookupByLibrary.simpleMessage("Register"),
    "requiredField": MessageLookupByLibrary.simpleMessage("Required field"),
    "resetPassword": MessageLookupByLibrary.simpleMessage("Reset password"),
    "sessionExpired": MessageLookupByLibrary.simpleMessage("Session expired"),
    "somethingWentWrong": MessageLookupByLibrary.simpleMessage(
      "Something went wrong",
    ),
    "tryAgainLater": MessageLookupByLibrary.simpleMessage(
      "Please try again later.",
    ),
  };
}
