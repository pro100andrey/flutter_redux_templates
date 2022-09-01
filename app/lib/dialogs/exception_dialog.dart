import 'package:async_redux/async_redux.dart';
import 'package:business/redux/app_state.dart';
import 'package:flutter/material.dart';
import 'package:localization/localization.dart';

/// Use it like this:
///
/// ```
/// class MyApp extends StatelessWidget {
///   @override
///   Widget build(BuildContext context)
///     => StoreProvider<AppState>(
///       store: store,
///       child: MaterialApp(
///           home: ExceptionDialog<AppState>(
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
    this.onShowUserExceptionDialog,
    this.useLocalContext = false,
    super.key,
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
        model: _Vm(),
        debug: this,
        builder: (context, vm) => _ExceptionDialogWidget(
          child,
          vm.error,
          onShowUserExceptionDialog,
          useLocalContext: useLocalContext,
        ),
      );
}

// ////////////////////////////////////////////////////////////////////////////

// ignore: prefer-single-widget-per-file
class _ExceptionDialogWidget extends StatefulWidget {
  const _ExceptionDialogWidget(
    this.child,
    this.error,
    ShowUserExceptionDialog? onShowUserExceptionDialog, {
    required this.useLocalContext,
  }) : onShowUserExceptionDialog = //
            onShowUserExceptionDialog ?? _defaultUserExceptionDialog;

  final Widget child;
  final Event<UserException>? error;
  final ShowUserExceptionDialog onShowUserExceptionDialog;
  final bool useLocalContext;

  static void _defaultUserExceptionDialog(
    BuildContext context,
    UserException userException,
    bool useLocalContext,
  ) {
    var resultContext = context;
    if (!useLocalContext) {
      final navigatorContext = NavigateAction.navigatorKey?.currentContext;
      if (navigatorContext != null) {
        resultContext = navigatorContext;
      }
    }

    final title = userException.dialogTitle();
    final content = userException.dialogContent();

    showDialogSuper<int>(
      context: resultContext,
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
      builder: (context) => AlertDialog(
        titleTextStyle: Theme.of(context).textTheme.headline6,
        contentTextStyle: Theme.of(context).textTheme.bodyText1,
        scrollable: true,
        title: Text(title),
        content: Text(content),
        actions: [
          if (userException.onCancel != null)
            TextButton(
              onPressed: () => Navigator.of(context).pop(2),
              child: Text(S.current.cancel),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(1),
            child: Text(S.current.ok),
          ),
        ],
      ),
    );
  }

  @override
  _UserExceptionDialogState createState() => _UserExceptionDialogState();
}

// ////////////////////////////////////////////////////////////////////////////

class _UserExceptionDialogState extends State<_ExceptionDialogWidget> {
  @override
  void didUpdateWidget(_ExceptionDialogWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    final userException = widget.error!.consume();

    if (userException != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onShowUserExceptionDialog(
          context,
          userException,
          widget.useLocalContext,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ////////////////////////////////////////////////////////////////////////////

class _Vm extends BaseModel<AppState> {
  _Vm();
  _Vm.build({required this.error});

  Event<UserException>? error;

  @override
  _Vm fromStore() => _Vm.build(
        error: Event(getAndRemoveFirstError()),
      );

  /// Does not respect equals contract:
  /// A==B ➜ true only if B.error.state is not null.
  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  bool operator ==(Object other) => error!.state == null;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  int get hashCode => error.hashCode;
}

// ////////////////////////////////////////////////////////////////////////////

typedef ShowUserExceptionDialog = void Function(
  BuildContext context,
  UserException userException,
  bool useLocalContext,
);

Future<T?> showDialogSuper<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  RouteSettings? routeSettings,
  void Function(T?)? onDismissed,
}) async {
  final result = await showDialog<T>(
    context: context,
    builder: builder,
    barrierDismissible: false,
    routeSettings: routeSettings,
  );

  onDismissed?.call(result);

  return result;
}
