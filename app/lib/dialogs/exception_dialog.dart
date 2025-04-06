import 'dart:collection';

import 'package:async_redux/async_redux.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Use it like this:
///
/// ```
/// class MyApp extends StatelessWidget {
///   @override
///   Widget build(BuildContext context)
///     => StoreProvider<AppState>(
///       store: store,
///       child: MaterialApp(
///           home: UserExceptionDialog<AppState>(
///             child: MyHomePage(),
///           )));
/// }
///
/// ```
///
/// For more info, see: https://pub.dartlang.org/packages/async_redux
///
class ExceptionDialog<St> extends StatelessWidget {
  const ExceptionDialog({
    required this.child,
    super.key,
    this.onShowUserExceptionDialog,
    this.useLocalContext = false,
  });
  final Widget child;
  final ShowUserExceptionDialog? onShowUserExceptionDialog;

  /// If false (the default), the dialog will appear in the context of the
  /// [NavigateAction.navigatorKey]. If you don't set up that key, or if you
  /// pass `true` here, it will use the local context of the
  /// [UserExceptionDialog] widget.
  ///
  /// Make sure this is `false` if you are putting the [UserExceptionDialog] in
  /// the `builder` parameter of the [MaterialApp] widget, because in this case
  /// the [UserExceptionDialog] will be above the app's [Navigator], and if
  /// you open the dialog in the local context you won't be able to use the
  /// Android back-button to close it.
  final bool useLocalContext;

  @override
  Widget build(BuildContext context) => StoreConnector<St, _Vm>(
    vm: _Factory<St>.new,
    builder: (context, vm) {
      //
      final errorEvent = //
          (_Factory._errorEvents.isEmpty) //
              ? null
              : _Factory._errorEvents.removeFirst();

      return _UserExceptionDialogWidget(
        errorEvent: errorEvent,
        useLocalContext: useLocalContext,
        onShowUserExceptionDialog: onShowUserExceptionDialog,
        child: child,
      );
    },
  );
}

class _UserExceptionDialogWidget extends StatefulWidget {
  const _UserExceptionDialogWidget({
    required this.child,
    required this.errorEvent,
    required this.useLocalContext,
    ShowUserExceptionDialog? onShowUserExceptionDialog,
  }) : onShowUserExceptionDialog = //
           onShowUserExceptionDialog ?? _defaultUserExceptionDialog;
  final Widget child;
  final Event<UserException>? errorEvent;
  final ShowUserExceptionDialog onShowUserExceptionDialog;
  final bool useLocalContext;

  static Future<void> _defaultUserExceptionDialog({
    required BuildContext context,
    required UserException userException,
    required bool useLocalContext,
  }) async {
    var ctx = context;
    if (!useLocalContext) {
      final navigatorContext = NavigateAction.navigatorKey?.currentContext;
      if (navigatorContext != null) {
        ctx = navigatorContext;
      }
    }

    await showDialogSuper<int>(
      context: ctx,
      onDismissed: (result) {
        if (result == 1) {
          userException.onOk?.call();
        } else if (result == 2) {
          userException.onCancel?.call();
        } else {
          if (userException.onCancel == null) {
            userException.onOk?.call();
          } else {
            userException.onCancel?.call();
          }
        }
      },
      builder: (context) {
        final (title, content) = userException.titleAndContent();
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            if (userException.onCancel != null)
              TextButton(
                child: const Text('CANCEL'),
                onPressed: () {
                  Navigator.of(context).pop(2);
                },
              ),
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop(1);
              },
            ),
          ],
        );
      },
    );
  }

  @override
  _UserExceptionDialogState createState() => _UserExceptionDialogState();
}

class _UserExceptionDialogState extends State<_UserExceptionDialogWidget> {
  @override
  void didUpdateWidget(_UserExceptionDialogWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    final userException = widget.errorEvent?.consume();

    if (userException != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onShowUserExceptionDialog(
          context: context,
          userException: userException,
          useLocalContext: widget.useLocalContext,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Factory<St> extends VmFactory<St, UserExceptionDialog, _Vm> {
  static final Queue<Event<UserException>> _errorEvents = Queue();

  @override
  _Vm fromStore() {
    final error = getAndRemoveFirstError();

    if (error != null) {
      _errorEvents.add(Event(error));
    }

    return _Vm(rebuild: error != null);
  }
}

class _Vm extends Vm {
  _Vm({required this.rebuild});
  //
  final bool rebuild;

  /// Does not respect equals contract:
  /// Is not equal when it should rebuild.
  @override
  bool operator ==(Object other) => !rebuild;

  @override
  int get hashCode => rebuild.hashCode;
}

typedef ShowUserExceptionDialog =
    void Function({
      required BuildContext context,
      required UserException userException,
      required bool useLocalContext,
    });

Future<T?> showDialogSuper<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor = Colors.black54,
  String? barrierLabel,
  bool useSafeArea = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  void Function(T?)? onDismissed,
}) async {
  final result = await showDialog<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    barrierLabel: barrierLabel,
    useSafeArea: useSafeArea,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
  );

  if (onDismissed != null) {
    onDismissed(result);
  }

  return result;
}

Future<T?> showCupertinoDialogSuper<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor = Colors.black54,
  String? barrierLabel,
  bool useSafeArea = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  void Function(T?)? onDismissed,
}) async {
  final result = await showCupertinoDialog<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierLabel,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
  );

  if (onDismissed != null) {
    onDismissed(result);
  }

  return result;
}
