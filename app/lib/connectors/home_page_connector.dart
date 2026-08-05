import 'package:async_redux/async_redux.dart';
import 'package:auto_route/auto_route.dart';
import 'package:business/redux/app_state.dart';
import 'package:business/redux/session/actions/set_token_action.dart';
import 'package:flutter/material.dart';
import 'package:ui/pages/home_page.dart';

@RoutePage()
class HomePageConnector extends StatelessWidget {
  const HomePageConnector({super.key});

  @override
  Widget build(BuildContext context) => StoreConnector<AppState, _Vm>(
    debug: this,
    vm: () => _Factory(this),
    builder: (context, vm) => HomePage(onPressedLogOut: vm.onPressedLogOut),
  );
}

/// Factory that creates a view-model for the StoreConnector.
class _Factory extends VmFactory<AppState, HomePageConnector, _Vm> {
  _Factory(super._connector);

  @override
  _Vm fromStore() => _Vm(
    // The only caller of `SetTokenAction`, and the app's only way out. Without
    // it a token could be written and never cleared, so a session — once
    // started — outlived every attempt to end it and came back from the
    // persistor on the next launch.
    onPressedLogOut: () => dispatchSync(SetTokenAction(value: null)),
  );
}

/// The view-model holds the part of the Store state the dumb-widget needs.
///
/// `equals` is empty because there is nothing here to compare: the one member
/// is a callback, and callbacks are rebuilt fresh on every `fromStore`, so
/// counting one would rebuild this screen on every dispatch in the app. It used
/// to hold an `isWaiting` that was a literal `false` — a full StoreConnector
/// subscribed to the whole store to compute a constant nothing read.
class _Vm extends Vm {
  _Vm({required this.onPressedLogOut}) : super(equals: const []);

  final VoidCallback onPressedLogOut;
}
