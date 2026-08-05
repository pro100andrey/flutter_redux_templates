import 'package:async_redux/async_redux.dart';
import 'package:business/redux/models/localized_message.dart';
import 'package:localization/localization.dart';

/// Turns anything thrown from a reducer into the title and body the user sees.
///
/// Handed to `createStore(onError:)`. It lives in `app` because this is the
/// only package that may name `S` — `business` describes the *shape* of a
/// translated message and the signature of a translator, never the locale
/// itself. That is the whole reason [LocalizedMessage] exists, and until this
/// function was wired the type was constructed nowhere in the repository.
///
/// Returns null for a [UserException], and only for that. Null means "I have
/// nothing to add", and `_MyErrorObserver` then passes the exception through
/// untouched — which matters, because a `UserException` can carry `onOk` /
/// `onCancel` callbacks and a `code` that re-wrapping would drop. Its message
/// was written for a person already.
///
/// Everything else is a Dart object that happened to reach the top. Its
/// `toString()` is not copy: `_MyErrorObserver` already logs the detail, so the
/// dialog gets a sentence instead.
LocalizedMessage? translateError(Object? error) => switch (error) {
  UserException() => null,
  _ => LocalizedMessage(
    title: S.current.somethingWentWrong,
    message: S.current.tryAgainLater,
  ),
};
