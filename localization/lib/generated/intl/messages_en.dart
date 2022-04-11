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
        "backToLogIn": MessageLookupByLibrary.simpleMessage("Back to logIn"),
        "cancel": MessageLookupByLibrary.simpleMessage("Cancel"),
        "confirmPassword":
            MessageLookupByLibrary.simpleMessage("Confirm Password"),
        "couldNotConnectToInternet": MessageLookupByLibrary.simpleMessage(
            "Couldn\'t connect to internet."),
        "email": MessageLookupByLibrary.simpleMessage("Email"),
        "emailInvalid":
            MessageLookupByLibrary.simpleMessage("Email is invalid"),
        "forgotPassword":
            MessageLookupByLibrary.simpleMessage("Forgot password ?"),
        "invalidEmail": MessageLookupByLibrary.simpleMessage("Invalid email"),
        "logIn": MessageLookupByLibrary.simpleMessage("Log in"),
        "minimumLengthSymbols": m0,
        "mustContainAtLeastOneLowercase": MessageLookupByLibrary.simpleMessage(
            "Must contain at least one lowercase"),
        "mustContainAtLeastOneUppercase": MessageLookupByLibrary.simpleMessage(
            "Must contain at least one uppercase"),
        "ok": MessageLookupByLibrary.simpleMessage("OK"),
        "password": MessageLookupByLibrary.simpleMessage("Password"),
        "passwordsDoNotMatch":
            MessageLookupByLibrary.simpleMessage("Passwords do not match"),
        "pleaseCheckYorNetworkSettings": MessageLookupByLibrary.simpleMessage(
            "Please check yor network settings."),
        "register": MessageLookupByLibrary.simpleMessage("Register"),
        "resetPassword": MessageLookupByLibrary.simpleMessage("Reset password"),
        "thisFieldIsRequired":
            MessageLookupByLibrary.simpleMessage("This field is required"),
        "title": MessageLookupByLibrary.simpleMessage("title")
      };
}
